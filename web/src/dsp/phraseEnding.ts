// 기준값은 iOS 앱과 같은 파일을 쓴다 (한 곳만 고치면 둘 다 바뀐다).
import rulesJson from '../../../VoicePractice/Models/PhraseEndingRules.json'
import { READING_INTERVAL, type PitchReading } from './pitchHistory'
import { semitones } from './pitchScale'
import { PitchSummary } from './pitchSummary'
import { contains, type Range } from './range'

/**
 * 구절별 문장 끝 분석의 기준값 (iOS `PhraseEndingRules`). 값은 `VoicePractice/Models/PhraseEndingRules.json`에 있고,
 * 각 값의 뜻은 그 파일의 `notes`에 적어 두었다. 시간은 [s], 높이는 [Hz], 하강 폭은 [반음]이다.
 */
export interface PhraseEndingRules {
  readonly phraseBreakSilenceSeconds: number
  readonly minimumPhraseVoicedSeconds: number
  readonly endWindowSeconds: number
  readonly endFloorPercentile: number
  readonly riseMaxDropSemitones: number
  readonly stableMaxDropSemitones: number
  readonly fallingMaxDropSemitones: number
  readonly fryFloorHz: number
  readonly fryMedianRatio: number
  readonly fryMinimumFrames: number
  readonly fryReferenceFrameSeconds: number
}

/** 앱에 들어 있는 기준값 */
export const PHRASE_ENDING_RULES: PhraseEndingRules = rulesJson

/** [s] 시각을 비교할 때의 여유. 부동소수 반올림 때문에 경계에 딱 걸친 프레임이 빠지지 않게 한다 */
export const PHRASE_TIME_TOLERANCE = 1e-9

/**
 * 긁히는 소리 가능성으로 볼 최소 연속 프레임 수를 실제 프레임 간격으로 환산한다 (iOS `fryMinimumRun`).
 * 기준은 10 ms 간격의 5프레임(= 50 ms)이다. 48 kHz의 21.3 ms 간격이면 ⌈50 / 21.3⌉ = 3프레임.
 * 올림이라 기준 시간보다 짧은 연속은 세지 않는다.
 */
export function fryMinimumRun(rules: PhraseEndingRules, frameInterval: number): number {
  const duration = rules.fryMinimumFrames * rules.fryReferenceFrameSeconds // [s]
  return Math.max(1, Math.ceil(duration / frameInterval - PHRASE_TIME_TOLERANCE))
}

/**
 * 문장 끝이 어떻게 움직였는지 (iOS `PhraseEndType`). 하강 폭 [반음] = 12·log₂(구절 중앙값 ÷ 끝 중앙값)으로 가른다.
 * rise: 끝이 올라감 (질문 억양, 감점하지 않음) / stable: 하강 폭이 작다 / falling: 조금 크게 내려감 / dropping: 크게 내려감
 */
export type PhraseEndType = 'rise' | 'stable' | 'falling' | 'dropping'

export function phraseEndType(drop: number, rules: PhraseEndingRules): PhraseEndType {
  if (drop <= rules.riseMaxDropSemitones) return 'rise'
  if (drop <= rules.stableMaxDropSemitones) return 'stable'
  if (drop <= rules.fallingMaxDropSemitones) return 'falling'
  return 'dropping'
}

/** 구절 하나의 문장 끝 (iOS `PhraseEnding`). */
export interface PhraseEnding {
  /** [s] 구절의 첫 유성 프레임 시각 */
  readonly startTime: number
  /** [s] 구절의 마지막 유성 프레임 시각 */
  readonly endTime: number
  /** 구절 전체의 유성 프레임 수 */
  readonly voicedFrameCount: number
  /** 문장 끝(마지막 `endWindowSeconds`) 안의 유성 프레임 수 */
  readonly endFrameCount: number
  /** [Hz] 구절 전체 유성 프레임의 중앙값 */
  readonly phraseMedian: number
  /** [Hz] 문장 끝 유성 프레임의 중앙값 */
  readonly endMedian: number
  /** [Hz] 문장 끝의 바닥 (10번째 백분위수). 최솟값 대신 써서 검출 오류로 튀는 값을 뺀다 */
  readonly endFloor: number
  /** [반음] 12·log₂(phraseMedian ÷ endMedian). +면 끝이 내려갔다 */
  readonly endDropSemitones: number
  /** 끝 바닥이 목표 하한보다 낮은지. 목표 범위가 없으면 null */
  readonly endBelowTarget: boolean | null
  readonly endType: PhraseEndType
  /** 문장 끝에 아주 낮은 프레임이 이어졌는지. 긁히는 소리(보컬 프라이)일 수도, 옥타브 오류일 수도 있다 */
  readonly possibleFry: boolean
}

/** 녹음 한 번의 문장 끝 요약 (iOS `PhraseEndingSummary`). */
export interface PhraseEndingSummary {
  readonly phraseCount: number
  /** [반음] 구절마다의 하강 폭 평균. 구절이 없으면 null */
  readonly meanEndDropSemitones: number | null
  /** ‘falling’·‘dropping’ 구절 수 */
  readonly fallingOrDroppingCount: number
  /** 0~1. ‘falling’·‘dropping’ 구절의 비율. 구절이 없으면 null */
  readonly fallingOrDroppingFraction: number | null
  /** 끝 바닥이 목표 하한 아래인 구절 수. 목표 범위가 없으면 null */
  readonly endBelowTargetCount: number | null
  /** 긁히는 소리 가능성이 있는 구절 수 */
  readonly possibleFryCount: number
  /** 0~1. 목표 범위 밖 유성 프레임 중 문장 끝에 든 비율. 목표 범위가 없거나 밖 프레임이 없으면 null */
  readonly outOfTargetAtEndFraction: number | null
  /** 0~1. 전체 유성 프레임 중 문장 끝에 든 비율. 위 비율과 견줄 기준이다. 유성 프레임이 없으면 null */
  readonly endFrameShare: number | null
}

/** 녹음 한 번의 구절별 문장 끝 분석 (iOS `PhraseEndingAnalysis`). */
export interface PhraseEndingAnalysis {
  /** 계산에 쓴 기준값과 목표 범위 (화면 글·요청문이 같은 숫자를 쓰게 함께 둔다) */
  readonly rules: PhraseEndingRules
  readonly target: Range | null
  /** [s] 피치 점 사이 간격 (48 kHz에서 약 21.3 ms, 샘플레이트에 따라 다르다) */
  readonly frameInterval: number
  readonly phrases: readonly PhraseEnding[]
  readonly summary: PhraseEndingSummary
}

interface Frame {
  readonly time: number // [s]
  readonly frequency: number // [Hz]
}

/**
 * 녹음 한 번을 구절로 나누고, 구절마다 문장 끝이 얼마나 내려갔는지 잰다 (iOS `PhraseEndingAnalysis.init`).
 * 입력은 피치 점(무성음은 frequency === null)과 사용자가 정한 목표 범위뿐이다. 화면과 상관없는 계산만 한다.
 * iOS 코드를 줄 단위로 옮겼다. 한쪽을 고치면 다른 쪽도 고친다. `readings`는 시간 순서여야 한다.
 */
export function analyzePhraseEndings(
  readings: readonly PitchReading[],
  target: Range | null,
  rules: PhraseEndingRules = PHRASE_ENDING_RULES,
): PhraseEndingAnalysis {
  const interval = phraseFrameInterval(readings)
  const voiced: Frame[] = readings.flatMap((reading) =>
    reading.frequency === null ? [] : [{ time: reading.time, frequency: reading.frequency }],
  )

  // 1. 구절 나누기: 이웃한 유성 프레임 사이의 무성음 길이(시각 차이 − 한 칸)가 기준 이상이면 끊는다.
  const groups: Frame[][] = []
  for (const frame of voiced) {
    const current = groups.at(-1)
    const last = current?.at(-1)
    if (
      current !== undefined &&
      last !== undefined &&
      frame.time - last.time - interval < rules.phraseBreakSilenceSeconds - PHRASE_TIME_TOLERANCE
    ) {
      current.push(frame)
    } else {
      groups.push([frame])
    }
  }

  // 2. 구절마다 문장 끝 재기. 유성음이 너무 짧은 구절은 버린다.
  const phrases: PhraseEnding[] = []
  let endFrames = 0
  let outOfTargetAtEnd = 0
  for (const group of groups) {
    if (!(group.length * interval >= rules.minimumPhraseVoicedSeconds - PHRASE_TIME_TOLERANCE)) continue
    const lastTime = group[group.length - 1].time
    const ending = group.filter((frame) => frame.time >= lastTime - rules.endWindowSeconds - PHRASE_TIME_TOLERANCE)
    const endSorted = ending.map((frame) => frame.frequency).sort((a, b) => a - b)

    const phraseMedian = PitchSummary.percentile(
      group.map((frame) => frame.frequency).sort((a, b) => a - b),
      0.5,
    )
    const endMedian = PitchSummary.percentile(endSorted, 0.5)
    const endFloor = PitchSummary.percentile(endSorted, rules.endFloorPercentile)
    const drop = semitones(endMedian, phraseMedian)
    const fryCeiling = Math.max(rules.fryFloorHz, phraseMedian * rules.fryMedianRatio) // [Hz]
    const fryRun = longestRun(ending, fryCeiling, interval)

    phrases.push({
      startTime: group[0].time,
      endTime: lastTime,
      voicedFrameCount: group.length,
      endFrameCount: ending.length,
      phraseMedian,
      endMedian,
      endFloor,
      endDropSemitones: drop,
      endBelowTarget: target === null ? null : endFloor < target.lower,
      endType: phraseEndType(drop, rules),
      possibleFry: fryRun >= fryMinimumRun(rules, interval),
    })
    endFrames += ending.length
    if (target !== null) {
      outOfTargetAtEnd += ending.filter((frame) => !contains(target, frame.frequency)).length
    }
  }

  // 3. 녹음 전체 요약. 목표 밖 프레임은 버린 구절까지 포함한 전체 유성 프레임에서 센다 (요약 카드의 ‘목표 범위 안’과 같은 기준).
  const outOfTarget = target === null ? null : voiced.filter((frame) => !contains(target, frame.frequency)).length
  const fallingOrDropping = phrases.filter((p) => p.endType === 'falling' || p.endType === 'dropping').length
  const count = phrases.length

  return {
    rules,
    target,
    frameInterval: interval,
    phrases,
    summary: {
      phraseCount: count,
      meanEndDropSemitones: count === 0 ? null : phrases.map((p) => p.endDropSemitones).reduce((a, b) => a + b, 0) / count,
      fallingOrDroppingCount: fallingOrDropping,
      fallingOrDroppingFraction: count === 0 ? null : fallingOrDropping / count,
      endBelowTargetCount: target === null ? null : phrases.filter((p) => p.endBelowTarget === true).length,
      possibleFryCount: phrases.filter((p) => p.possibleFry).length,
      outOfTargetAtEndFraction: outOfTarget === null || outOfTarget === 0 ? null : outOfTargetAtEnd / outOfTarget,
      endFrameShare: voiced.length === 0 ? null : endFrames / voiced.length,
    },
  }
}

/**
 * [s] 피치 점 사이 간격: 이웃한 점의 시각 차이의 중앙값. 점이 둘보다 적으면 48 kHz의 기본 간격 (iOS `frameInterval(of:)`).
 * 샘플레이트에 따라 간격이 달라서(44.1 kHz 23.2 ms, 16 kHz 파일 64 ms) 녹음마다 알아낸다.
 */
export function phraseFrameInterval(readings: readonly PitchReading[]): number {
  const gaps: number[] = []
  for (let i = 1; i < readings.length; i++) {
    const gap = readings[i].time - readings[i - 1].time
    if (gap > 0) gaps.push(gap)
  }
  return gaps.length === 0 ? READING_INTERVAL : PitchSummary.percentile(gaps.sort((a, b) => a - b), 0.5)
}

/**
 * `frames`(시간 순서의 유성 프레임)에서 `ceiling` [Hz]보다 낮은 프레임이 가장 길게 이어진 수.
 * 사이에 무성음 프레임이 끼면(시각 차이가 한 칸 반보다 크면) 이어진 것으로 보지 않는다.
 */
function longestRun(frames: readonly Frame[], ceiling: number, interval: number): number {
  let longest = 0
  let run = 0
  let previousTime: number | null = null
  for (const frame of frames) {
    const adjacent = previousTime !== null && frame.time - previousTime <= interval * 1.5
    run = frame.frequency < ceiling ? (adjacent ? run : 0) + 1 : 0
    longest = Math.max(longest, run)
    previousTime = frame.time
  }
  return longest
}
