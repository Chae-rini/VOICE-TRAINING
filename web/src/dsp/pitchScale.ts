import { FREQUENCY_RANGE } from './pitchDetector'
import { contains, type Range } from './range'

/**
 * 높이(Hz)를 반음 눈금으로 다루는 규칙 (iOS `Models/PitchScale.swift`).
 * 사람은 높이를 Hz의 차이가 아니라 비율로 느낀다 (반음 하나 = 2^(1/12)배, 약 6%).
 * 그래서 그래프는 Hz를 반음 간격으로 놓는다. 어느 높이에서든 같은 반음 폭이 같은 길이로 그려진다 (원칙 3).
 * 저장하는 값과 화면의 숫자는 계속 Hz다. 위치만 반음 간격이다.
 */

/** [반음] a에서 b까지: 12·log₂(b/a). b가 높으면 +, 낮으면 −. */
export function semitones(from: number, to: number): number {
  return 12 * Math.log2(to / from)
}

/** [Hz] `frequency`에서 반음 `semitoneOffset`개만큼 옮긴 높이 */
export function offsetBySemitones(frequency: number, semitoneOffset: number): number {
  return frequency * Math.pow(2, semitoneOffset / 12)
}

/** `r` 안의 상대 위치 (아래 끝 0, 위 끝 1). 반음 간격이라 같은 반음 폭은 어디서든 같은 길이다. */
export function position(frequency: number, r: Range): number {
  return Math.log(frequency / r.lower) / Math.log(r.upper / r.lower)
}

/** `position`의 반대: 상대 위치(0~1) → Hz */
export function frequencyAtPosition(p: number, r: Range): number {
  return r.lower * Math.pow(r.upper / r.lower, p)
}

/**
 * [Hz] [높이] 그래프 세로축의 여유: 목표 범위 위아래로 이만큼만 보여 준다 (2026-10-25 사용자 요청 "밴드 ±50 Hz").
 * 70~400 Hz 전체를 그리면 목표 근처의 움직임이 작게 보여서, 목표 범위 둘레를 크게 본다.
 */
export const GRAPH_MARGIN = 50

/** [높이] 그래프 세로축 범위: 목표 범위 ±50 Hz (분석 범위 70~400 Hz 안으로). 목표 범위가 없으면 분석 범위 전체. */
export function graphRange(target: Range | null, full: Range = FREQUENCY_RANGE): Range {
  if (target === null) {
    return full
  }
  const lower = Math.max(target.lower - GRAPH_MARGIN, full.lower)
  const upper = Math.min(target.upper + GRAPH_MARGIN, full.upper)
  return lower < upper ? { lower, upper } : full
}

/**
 * 두 높이 [Hz]가 모두 `r`의 같은 쪽 밖에 있는가. 그래프는 이 구간을 끝에 붙인 점선으로 그린다
 * (끝에 붙인 실선은 "그 높이로 평평하게 냈다"로 읽히기 쉬워서).
 */
export function isBeyond(a: number, b: number, r: Range): boolean {
  return (a > r.upper && b > r.upper) || (a < r.lower && b < r.lower)
}

/** 눈금 후보. 반음 눈금에서 고르게 보이는 숫자를 성긴 것부터 고른다. */
const TICK_SETS: readonly (readonly number[])[] = [
  [70, 100, 150, 200, 300, 400],
  [70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 350, 400],
  Array.from({ length: 34 }, (_, i) => 70 + 10 * i), // 70, 80, …, 400
]

/** `r` 안의 눈금 [Hz]. 가장 성긴 묶음부터 보고, 눈금이 `minimumCount`개(기본 3개) 이상 들어가는 첫 묶음을 쓴다. */
export function ticks(r: Range, minimumCount = 3): number[] {
  for (const set of TICK_SETS) {
    const inside = set.filter((value) => contains(r, value))
    if (inside.length >= minimumCount) {
      return inside
    }
  }
  return TICK_SETS[TICK_SETS.length - 1].filter((value) => contains(r, value))
}
