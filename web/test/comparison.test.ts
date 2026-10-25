import { describe, expect, it } from 'vitest'
import { offsetBySemitones, semitones } from '../src/dsp/pitchScale'
import { contains, range } from '../src/dsp/range'
import {
  comparisonDomain,
  defaultPair,
  distribution,
  medianDifferenceText,
  rangeSemitones,
} from '../src/model/comparison'
import { MINIMUM_PITCH_SPAN_SEMITONES } from '../src/model/history'

// iOS VoicePracticeTests/RecordingComparisonTests.swift를 옮겼다 (소리 파일을 읽는 재생기 시험은 브라우저에서 확인한다).
describe('RecordingComparison (두 녹음 비교)', () => {
  it('처음 짝은 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B), 두 개가 안 되면 없음', () => {
    const dates = [new Date(300_000), new Date(100_000), new Date(200_000)]
    expect(defaultPair(dates, (d) => d)).toEqual({ a: dates[1], b: dates[0] })
    expect(defaultPair([dates[0]], (d) => d)).toBeNull()
  })

  it('높낮이 폭은 범위를 반음으로 센 값', () => {
    expect(rangeSemitones(100, 200)).toBeCloseTo(12, 9)
    expect(rangeSemitones(150, 150)).toBe(0)
    expect(rangeSemitones(0, 150)).toBe(0)
  })

  it.each([
    [150, 162, 'B의 중앙값이 A보다 12 Hz 높아요 (반음 약 1.3개).'],
    [200, 180, 'B의 중앙값이 A보다 20 Hz 낮아요 (반음 약 1.8개).'],
    [150, 150.5, '두 녹음의 중앙값이 거의 같아요 (1 Hz 미만 차이).'],
  ])('중앙값 차이는 높다·낮다는 사실과 반음 수만 말한다: %d → %d Hz', (a, b, expected) => {
    const text = medianDifferenceText(a, b)
    expect(text).toBe(expected)
    for (const judgement of ['좋', '나빠', '개선', '남성', '여성']) expect(text).not.toContain(judgement)
  })

  it('높이 분포: 반음 반 칸마다 비율, 범위 밖 점은 칸에 넣지 않되 전체 수에는 넣는다', () => {
    const values = [150, 151, 152, 157, 180]
    const bins = distribution(values, range(150, 185))
    // 칸 가운데끼리는 반음 반 칸(2^(1/24)배)씩 떨어져 있다
    for (let i = 1; i < bins.length; i++) expect(semitones(bins[i - 1].center, bins[i].center)).toBeCloseTo(0.5, 9)
    // 150~185 Hz는 반음 약 3.6개 → 칸 7~9개
    expect(bins.length).toBeGreaterThanOrEqual(7)
    expect(bins.length).toBeLessThanOrEqual(9)
    expect(bins.reduce((sum, bin) => sum + bin.fraction, 0)).toBeCloseTo(1, 9)
    // 각 점은 자기 높이를 감싸는 칸(가운데에서 반음 ±0.25)에 들어간다
    for (const value of values) {
      const home = bins.reduce((best, bin) =>
        Math.abs(semitones(bin.center, value)) < Math.abs(semitones(best.center, value)) ? bin : best,
      )
      expect(Math.abs(semitones(home.center, value))).toBeLessThanOrEqual(0.25 + 1e-9)
      expect(home.fraction).toBeGreaterThan(0)
    }

    const withOutlier = distribution([...values, 390], range(150, 185))
    expect(withOutlier.reduce((sum, bin) => sum + bin.fraction, 0)).toBeCloseTo(5 / 6, 9)
    expect(distribution([], range(150, 185))).toEqual([])
  })

  it('같은 반음만큼 흔들리면 낮은 목소리든 높은 목소리든 비슷한 수의 칸에 퍼진다', () => {
    // 가운데에서 위아래 반음 1개씩 고르게 흔들린 목소리 (반음 2개 폭)
    const voice = (center: number) => Array.from({ length: 200 }, (_, i) => offsetBySemitones(center, -1 + (2 * i) / 199))
    const occupied = (voiced: number[]) =>
      distribution(voiced, range(Math.min(...voiced), Math.max(...voiced))).filter((bin) => bin.fraction > 0).length
    const low = occupied(voice(120))
    const high = occupied(voice(300))
    expect(Math.abs(low - high)).toBeLessThanOrEqual(1)
    expect(low).toBeGreaterThanOrEqual(4)
    expect(low).toBeLessThanOrEqual(5)
  })

  it('분포 그래프 가로축: 두 녹음과 목표 범위가 들어가고, 드물게 튄 값은 뺀다', () => {
    const a = Array.from({ length: 100 }, (_, i) => 140 + i * 0.2) // 140~160 Hz
    const b = [...Array.from({ length: 100 }, (_, i) => 170 + i * 0.2), 395] // 170~190 Hz, 한 번 튄 값
    const domain = comparisonDomain(a, b, range(200, 220))
    expect(contains(domain, 140)).toBe(true)
    expect(contains(domain, 190)).toBe(true)
    expect(contains(domain, 220)).toBe(true)
    expect(contains(domain, 395)).toBe(false)
    expect(semitones(domain.lower, domain.upper)).toBeGreaterThanOrEqual(MINIMUM_PITCH_SPAN_SEMITONES - 1e-9)
  })
})
