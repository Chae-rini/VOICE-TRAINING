import type { PitchReading } from './pitchHistory'
import { PitchSummary } from './pitchSummary'
import { range } from './range'

/**
 * F1이 불확실한지 (iOS `Models/VowelSpace.swift`): 목소리가 높고(F0 ≥ 200 Hz) F1이 2.5×F0보다 낮으면
 * 가까운 배음으로 끌렸을 수 있다. 합성 모음 검증에서 F0 200 Hz 이상, F1이 낮은 모음에서 최대 20~36% 오차를 본 것을 바탕으로 정했다.
 */
export function isF1Uncertain(f1: number, f0: number): boolean {
  return f0 >= 200 && f1 < 2.5 * f0
}

/** 지도 위 한 점 (흔들림을 줄인 값) */
export interface VowelPoint {
  /** [Hz] */
  readonly f1: number
  /** [Hz] */
  readonly f2: number
  /** 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음 */
  readonly isF1Uncertain: boolean
}

/** 목소리와 포먼트가 함께 잡힌 점만 (F0, F1, F2) */
export function voicedFormants(readings: readonly PitchReading[]): { f0: number; f1: number; f2: number }[] {
  return readings.flatMap((r) =>
    r.frequency === null || !r.formants ? [] : [{ f0: r.frequency, f1: r.formants.f1.frequency, f2: r.formants.f2.frequency }],
  )
}

function median(values: number[]): number {
  return PitchSummary.percentile(values.sort((a, b) => a - b), 0.5)
}

/**
 * 모음 지도(F1–F2 평면)의 규칙 (iOS `VowelSpace`).
 * 방향은 음성학의 모음도와 같다: 가로는 F2가 높을수록 왼쪽(혀 앞쪽), 세로는 F1이 낮을수록 위(입을 좁게).
 * 성별 평균 같은 기준 위치는 두지 않는다 (원칙 3). 비교 대상은 내가 잰 내 모음뿐이다.
 */
export const VowelSpace = {
  /** [Hz] 지도에 보이는 F1 범위 (세로) */
  f1Range: range(200, 1100),
  /** [Hz] 지도에 보이는 F2 범위 (가로) */
  f2Range: range(600, 3000),
  /** [Hz] 눈금 */
  f1Ticks: [300, 500, 700, 900] as readonly number[],
  f2Ticks: [1000, 1500, 2000, 2500] as readonly number[],

  /** 최근 점들(포먼트가 잡힌 것)의 중앙값. 3개 미만이면 null — 한두 조각만으로는 흔들려서 보여 주지 않는다. */
  current(readings: readonly PitchReading[]): VowelPoint | null {
    const voiced = voicedFormants(readings)
    if (voiced.length < 3) return null
    const f1 = median(voiced.map((v) => v.f1))
    const f2 = median(voiced.map((v) => v.f2))
    const f0 = median(voiced.map((v) => v.f0))
    return { f1, f2, isF1Uncertain: isF1Uncertain(f1, f0) }
  },

  /** 지도 안의 상대 위치 (0~1, 왼쪽 위가 (0, 0)). 범위를 벗어나면 가장자리에 붙인다. */
  position(f1: number, f2: number): { x: number; y: number } {
    const { f1Range, f2Range } = VowelSpace
    const x = 1 - (f2 - f2Range.lower) / (f2Range.upper - f2Range.lower)
    const y = (f1 - f1Range.lower) / (f1Range.upper - f1Range.lower)
    return { x: Math.min(Math.max(x, 0), 1), y: Math.min(Math.max(y, 0), 1) }
  },
}
