import type { FormantEstimate } from './formantAnalyzer'
import type { PitchReading } from './pitchHistory'
import { semitones } from './pitchScale'
import { PitchSummary } from './pitchSummary'
import { isF1Uncertain } from './vowelSpace'

/**
 * [높이] 탭의 음량 막대 계산 (iOS `Models/VoiceMeters.swift`).
 * 소리 크기는 이 기기 마이크가 받은 크기(dBFS, 0이 마이크가 받을 수 있는 최대)라 기기마다 다르다.
 * 귀에 들리는 절대 크기(dB SPL)가 아니므로 크다·작다를 평가하지 않고, 아주 큰 소리가 이어질 때만 목 상태를 묻는다 (원칙 4).
 */
export const LevelMeter = {
  /** [dBFS] 막대 범위 */
  range: { lower: -60, upper: 0 },
  /** [dBFS] 무음(RMS 0)을 나타내는 값 */
  floor: -100,
  /** [s] 평활 길이: 최근 이만큼의 소리 세기를 평균한다 */
  smoothingSeconds: 0.3,
  /** [dBFS] 큰 소리 기준 (임시값). 아이폰 값을 확인한 뒤 iOS와 함께 고친다. */
  loudThreshold: -10,
  /** [s] 큰 소리가 이만큼 이어지면 안내한다 (임시값) */
  loudSeconds: 3,
  /** 그 시간 동안 이 비율 이상의 조각이 기준을 넘으면 '이어졌다'고 본다 (숨 쉬는 짧은 틈은 봐준다) */
  loudFraction: 0.8,

  /** 소리 조각 하나의 크기 [dBFS]: 20·log₁₀(RMS). 무음이면 `floor`. */
  dBFS(rms: number): number {
    return rms > 0 ? Math.max(20 * Math.log10(rms), LevelMeter.floor) : LevelMeter.floor
  },

  /** `time` 직전 0.3초의 평균 크기 [dBFS]. 크기를 dB로 평균하지 않고 세기(RMS²)로 평균한 뒤 dB로 바꾼다. 점이 없으면 null. */
  smoothedLevel(readings: Iterable<PitchReading>, time: number): number | null {
    const levels: number[] = []
    for (const reading of readings) {
      if (reading.time > time - LevelMeter.smoothingSeconds && reading.time <= time && reading.level != null) {
        levels.push(reading.level)
      }
    }
    if (levels.length === 0) return null
    const power = levels.reduce((total, level) => total + Math.pow(10, level / 10), 0) / levels.length
    return LevelMeter.dBFS(Math.sqrt(power))
  },

  /** 큰 소리가 `loudSeconds`초 넘게 이어졌는지: 그 시간을 거의 다 채운 점들 중 80% 이상이 기준을 넘으면. */
  isSustainedLoud(readings: Iterable<PitchReading>, time: number): boolean {
    const recent: PitchReading[] = []
    for (const reading of readings) {
      if (reading.time > time - LevelMeter.loudSeconds && reading.time <= time && reading.level != null) {
        recent.push(reading)
      }
    }
    const first = recent[0]
    if (first === undefined || time - first.time < LevelMeter.loudSeconds * 0.9) return false
    const loud = recent.filter((reading) => (reading.level ?? LevelMeter.floor) >= LevelMeter.loudThreshold).length
    return loud / recent.length >= LevelMeter.loudFraction
  },

  /** 막대에서의 위치 (0 왼쪽 끝 −60 dBFS ~ 1 오른쪽 끝 0 dBFS) */
  position(level: number): number {
    const { lower, upper } = LevelMeter.range
    return Math.min(Math.max((level - lower) / (upper - lower), 0), 1)
  },
}

export interface ResonanceReading {
  /** [Hz] F2 중앙값 */
  readonly f2: number
  /** 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음 (모음 지도와 같은 규칙) */
  readonly isUncertain: boolean
}

/**
 * [높이] 탭의 공명 밝기 막대 계산: 최근 목소리의 둘째 포먼트(F2)가 내 기준보다 밝은 쪽인지 어두운 쪽인지.
 * 성별 평균 같은 바깥 기준은 쓰지 않고 내 기준과만 비교한다 (원칙 3).
 * 문장 속 F2는 어떤 모음을 말했는지에 따라 크게 달라지므로, 같은 대본을 읽을 때 비교해야 뜻이 있다.
 */
export const ResonanceMeter = {
  /** [s] 최근 이만큼의 목소리 구간에서 F2 중앙값을 낸다 */
  windowSeconds: 2.5,
  /** 포먼트가 잡힌 점이 이보다 적으면(약 0.4초 분량) 흔들려서 보여 주지 않는다 */
  minimumPoints: 20,
  /** [반음] 막대 양 끝: 기준에서 어두운 쪽·밝은 쪽으로 이만큼 */
  halfRangeSemitones: 6,

  /** `time` 직전 2.5초 동안 목소리와 포먼트가 잡힌 점들의 F2 중앙값. 점이 20개보다 적으면 null. */
  current(readings: Iterable<PitchReading>, time: number): ResonanceReading | null {
    const voiced: { f0: number; formants: FormantEstimate }[] = []
    for (const reading of readings) {
      if (reading.time > time - ResonanceMeter.windowSeconds && reading.time <= time) {
        if (reading.frequency !== null && reading.formants != null) {
          voiced.push({ f0: reading.frequency, formants: reading.formants })
        }
      }
    }
    if (voiced.length < ResonanceMeter.minimumPoints) return null
    const median = (values: number[]) => PitchSummary.percentile(values.sort((a, b) => a - b), 0.5)
    const f2 = median(voiced.map((v) => v.formants.f2.frequency))
    const f1 = median(voiced.map((v) => v.formants.f1.frequency))
    const f0 = median(voiced.map((v) => v.f0))
    return { f2, isUncertain: isF1Uncertain(f1, f0) }
  },

  /** 녹음(또는 기준 재기) 전체의 F2 중앙값 [Hz]. 목소리와 포먼트가 잡힌 점이 20개보다 적으면 null. */
  median(readings: Iterable<PitchReading>): number | null {
    const values: number[] = []
    for (const reading of readings) {
      if (reading.frequency !== null && reading.formants != null) {
        values.push(reading.formants.f2.frequency)
      }
    }
    if (values.length < ResonanceMeter.minimumPoints) return null
    return PitchSummary.percentile(values.sort((a, b) => a - b), 0.5)
  },

  /** 기준 F2 대비 막대 위치 (0 어두운 끝, 0.5 기준, 1 밝은 끝). 반음 눈금이라 기준이 높든 낮든 같은 비율이 같은 거리다. */
  position(f2: number, baseline: number): number {
    const offset = semitones(baseline, f2)
    return Math.min(Math.max(0.5 + offset / (2 * ResonanceMeter.halfRangeSemitones), 0), 1)
  },
}
