import { PitchSummary } from '../dsp/pitchSummary'
import { FREQUENCY_RANGE } from '../dsp/pitchDetector'
import type { PitchReading } from '../dsp/pitchHistory'
import { semitones } from '../dsp/pitchScale'
import type { Range } from '../dsp/range'
import { ResonanceMeter } from '../dsp/voiceMeters'

/**
 * [높이] 화면의 규칙: 들려줄 길이, 내 기준 목소리, 목표 범위 (iOS `PracticeDuration.swift`·`VoiceBaseline.swift`·
 * `PitchGraphView.swift`의 TargetRangeControls). 화면과 저장에서 떼어 테스트한다.
 */

/** 들려줄 길이 [s]: 10초~3분, 10초 단위 (그래프 가로축 길이이기도 하다) */
export const PracticeDuration = {
  range: { lower: 10, upper: 180 },
  step: 10,
  defaultSeconds: 60,

  /** 범위 안으로 자르고 10초 단위로 맞춘다. */
  normalized(seconds: number): number {
    const snapped = Math.round(seconds / PracticeDuration.step) * PracticeDuration.step
    return Math.min(PracticeDuration.range.upper, Math.max(PracticeDuration.range.lower, snapped))
  },

  /** 예: 10 → "10초", 60 → "1분", 90 → "1분 30초" */
  label(seconds: number): string {
    const total = PracticeDuration.normalized(seconds)
    const minutes = Math.floor(total / 60)
    const remainder = total % 60
    if (minutes === 0) return `${remainder}초`
    return remainder === 0 ? `${minutes}분` : `${minutes}분 ${remainder}초`
  },

  /** 대본을 끝까지 읽을 수 있게 예상 시간을 10초 단위로 올림한다 */
  suggestedFor(estimatedSeconds: number): number {
    return PracticeDuration.normalized(Math.ceil(estimatedSeconds / PracticeDuration.step) * PracticeDuration.step)
  },
}

/**
 * 내 기준 목소리: 연습 문장을 편하게 읽었을 때 잰 피치.
 * 높다·낮다 같은 평가 없이, 목표 범위를 정하는 출발점으로만 쓴다. 이 기기(브라우저) 안에만 저장한다.
 */
export interface VoiceBaseline {
  /** [Hz] 피치 중앙값 */
  readonly median: number
  /** [Hz] 아래 10% 지점 */
  readonly low: number
  /** [Hz] 위 10% 지점 */
  readonly high: number
  /** [Hz] 둘째 포먼트(F2)의 중앙값 (공명 밝기 막대의 가운데). 포먼트가 충분히 잡히지 않았으면 null */
  readonly f2: number | null
}

export type BaselineMeasurement = { readonly kind: 'measured'; readonly baseline: VoiceBaseline } | { readonly kind: 'tooLittleVoice' }

export const Baseline = {
  /** [s] 마이크로 잴 때의 녹음 길이 */
  recordingSeconds: 10,
  /** [s] 목소리가 이보다 짧게 잡히면 다시 재자고 안내한다 */
  minimumVoicedSeconds: 2,
  /** [Hz] 처음 목표 범위는 기준 중앙값 ± 이 값 */
  initialTargetHalfWidth: 20,
  /** [반음] 목표 범위 가운데가 기준에서 이만큼 이상 떨어지면 부드럽게 안내한다. 위·아래 어느 쪽이든 같다 */
  farDistanceSemitones: 6,

  /** 피치 기록으로 기준 목소리를 잰다. 목소리가 잡힌 시간이 2초보다 짧으면 tooLittleVoice. */
  measure(readings: readonly PitchReading[]): BaselineMeasurement {
    const voiced = readings.flatMap((r) => (r.frequency === null ? [] : [r.frequency])).sort((a, b) => a - b)
    // 점 사이 간격(분석 간격)으로 목소리가 잡힌 시간을 어림한다 (PitchSummary와 같은 방식).
    const interval =
      readings.length > 1 ? (readings[readings.length - 1].time - readings[0].time) / (readings.length - 1) : 0
    if (!(voiced.length * interval >= Baseline.minimumVoicedSeconds)) return { kind: 'tooLittleVoice' }
    return {
      kind: 'measured',
      baseline: {
        median: PitchSummary.percentile(voiced, 0.5),
        low: PitchSummary.percentile(voiced, 0.1),
        high: PitchSummary.percentile(voiced, 0.9),
        f2: ResonanceMeter.median(readings),
      },
    }
  },

  /** 처음 목표 범위: 중앙값 ±20 Hz. 가운데를 슬라이더와 같은 5 Hz 단위로 맞추고, 그래프 범위(70~400 Hz) 안으로 민다. */
  initialTarget(baseline: VoiceBaseline): Range {
    const half = Baseline.initialTargetHalfWidth
    const center = Math.min(
      Math.max(Math.round(baseline.median / 5) * 5, FREQUENCY_RANGE.lower + half),
      FREQUENCY_RANGE.upper - half,
    )
    return { lower: center - half, upper: center + half }
  },

  /** 목표 범위 가운데가 기준 중앙값에서 반음 6개 이상 떨어졌는지 (방향 무관) */
  isFar(target: Range, median: number): boolean {
    const center = (target.lower + target.upper) / 2
    return Math.abs(semitones(median, center)) >= Baseline.farDistanceSemitones
  },
}

/** 목표 범위 슬라이더 규칙: 5 Hz 단위, 하한과 상한은 10 Hz 넘게 떨어져 있다. 슬라이더 범위는 그래프와 같은 70~400 Hz. */
export const TargetRange = {
  /** [Hz] 하한과 상한의 최소 간격 */
  minimumGap: 10,

  snapped(frequency: number): number {
    return Math.round(frequency / 5) * 5
  },

  /** 하한을 옮긴다 (상한 − 10 Hz를 넘지 않게) */
  withLower(target: Range, frequency: number): Range {
    return { lower: Math.min(TargetRange.snapped(frequency), target.upper - TargetRange.minimumGap), upper: target.upper }
  },

  /** 상한을 옮긴다 (하한 + 10 Hz보다 내려가지 않게) */
  withUpper(target: Range, frequency: number): Range {
    return { lower: target.lower, upper: Math.max(TargetRange.snapped(frequency), target.lower + TargetRange.minimumGap) }
  },

  /** "130 – 320 Hz" */
  label(target: Range): string {
    return `${Math.trunc(target.lower)} – ${Math.trunc(target.upper)} Hz`
  },
}
