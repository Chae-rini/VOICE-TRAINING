import { offsetBySemitones, semitones } from '../dsp/pitchScale'
import { PitchSummary } from '../dsp/pitchSummary'
import { contains, type Range } from '../dsp/range'
import { pitchDomain } from './history'

/**
 * 두 녹음 비교(A·B)의 계산 규칙 (iOS `Models/RecordingComparison.swift`). 어느 쪽이 낫다는 판정 없이 차이만 숫자로 말한다 (원칙 3).
 */

/** 높이 분포 한 칸 */
export interface ComparisonBin {
  /** [Hz] 칸의 가운데 (반음 눈금에서의 가운데) */
  readonly center: number
  /** 0~1. 목소리가 잡힌 점 중 이 칸에 든 비율 */
  readonly fraction: number
}

/**
 * 분포 칸: 반음 하나를 두 칸으로 (반음 반 칸). Hz로 일정한 칸이면 높은 목소리일수록 같은 흔들림이
 * 더 많은 칸에 퍼져 납작하게 그려지므로, 반음 눈금으로 나눈다.
 */
export const BINS_PER_SEMITONE = 2
/** [Hz] 칸의 기준점 (A4). 두 녹음이 같은 칸 경계를 쓰도록 고정해 둔다 */
export const BIN_REFERENCE = 440
/** [Hz] 중앙값 차이가 이보다 작으면 "거의 같아요" */
export const SAME_MEDIAN_THRESHOLD = 1

/** 처음 열 때의 짝: 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B). 두 개가 안 되면 null */
export function defaultPair<T>(items: readonly T[], date: (item: T) => Date): { a: T; b: T } | null {
  if (items.length < 2) return null
  const sorted = [...items].sort((x, y) => date(x).getTime() - date(y).getTime())
  return { a: sorted[0], b: sorted[sorted.length - 1] }
}

/** 높낮이 폭 [반음]: 아래 10%~위 10%를 반음으로 센 값, 12·log₂(high/low). 억양의 오르내림이 클수록 크다 */
export function rangeSemitones(low: number, high: number): number {
  return low > 0 && high > 0 ? semitones(low, high) : 0
}

/** B의 중앙값이 A와 얼마나 다른지 한 문장으로. 높다·낮다는 사실만 말하고 좋고 나쁨은 말하지 않는다 */
export function medianDifferenceText(a: number, b: number): string {
  const difference = b - a
  if (Math.abs(difference) < SAME_MEDIAN_THRESHOLD) return '두 녹음의 중앙값이 거의 같아요 (1 Hz 미만 차이).'
  const direction = difference > 0 ? '높아요' : '낮아요'
  return `B의 중앙값이 A보다 ${Math.round(Math.abs(difference))} Hz ${direction} (반음 약 ${Math.abs(semitones(a, b)).toFixed(1)}개).`
}

/**
 * 목소리 높이들을 `domain` 안에서 반음 반 칸으로 나눠 칸마다 비율을 낸다.
 * 범위 밖 점도 전체 수에는 넣는다 (잘린 쪽의 비율이 부풀지 않게).
 */
export function distribution(frequencies: readonly number[], domain: Range, binsPerSemitone = BINS_PER_SEMITONE): ComparisonBin[] {
  if (frequencies.length === 0) return []
  // 기준점(440 Hz)에서 반음 반 칸 몇 개 떨어졌는지 (아래로 내림)
  const index = (frequency: number) => Math.floor(semitones(BIN_REFERENCE, frequency) * binsPerSemitone)
  const first = index(domain.lower)
  const binCount = Math.max(index(domain.upper) - first + 1, 1)
  const counts = new Array<number>(binCount).fill(0)
  for (const frequency of frequencies) {
    if (!contains(domain, frequency)) continue
    counts[Math.min(Math.max(index(frequency) - first, 0), binCount - 1)] += 1
  }
  return counts.map((count, offset) => ({
    // [반음] 기준점에서 칸 가운데까지
    center: offsetBySemitones(BIN_REFERENCE, (first + offset + 0.5) / binsPerSemitone),
    fraction: count / frequencies.length,
  }))
}

/** 분포 그래프 가로축 [Hz]: 두 녹음의 아래 2%~위 2%와 목표 범위가 들어가게 (드물게 튀는 값은 뺀다) */
export function comparisonDomain(a: readonly number[], b: readonly number[], target: Range | null): Range {
  const values: number[] = []
  for (const voiced of [a, b]) {
    if (voiced.length === 0) continue
    const sorted = [...voiced].sort((x, y) => x - y)
    values.push(PitchSummary.percentile(sorted, 0.02), PitchSummary.percentile(sorted, 0.98))
  }
  return pitchDomain(values, target, null)
}
