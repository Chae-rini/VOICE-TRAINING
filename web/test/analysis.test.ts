import { describe, expect, it } from 'vitest'
import { analyzeSamples, MAX_PLAYBACK_GAIN, PLAYBACK_PEAK, playbackGain, readingsInTake } from '../src/dsp/analysis'
import { sine } from './signals'

describe('analyzeSamples (녹음 파일 분석과 같은 방식)', () => {
  it('2048샘플 창을 절반씩 밀며, 점의 시각은 창 한가운데다', () => {
    const readings = analyzeSamples(sine(200, 48_000, 48_000), 48_000)
    // ⌊(48000 − 2048) / 1024⌋ + 1 = 45개
    expect(readings).toHaveLength(45)
    expect(readings[0].time).toBeCloseTo(1024 / 48_000, 12)
    expect(readings[1].time - readings[0].time).toBeCloseTo(1024 / 48_000, 12)
    expect(readings.every((r) => r.frequency !== null && Math.abs(r.frequency - 200) < 0.5)).toBe(true)
    // 진폭 0.5 사인파: 약 −9 dBFS
    expect(Math.abs(readings[0].level! - 20 * Math.log10(0.5 / Math.SQRT2))).toBeLessThan(0.1)
  })

  it('무음 조각은 높이 없이 소리 크기(바닥값)만 남긴다', () => {
    const readings = analyzeSamples(new Float32Array(4096), 48_000)
    expect(readings).toHaveLength(3)
    expect(readings.every((r) => r.frequency === null && r.formants === null && r.level === -100)).toBe(true)
  })
})

// iOS PracticeLoopTests의 재생 배율 테스트를 옮겼다.
describe('playbackGain (다시 듣기 음량)', () => {
  it.each([
    [0.089, 10], // −21 dBFS → 10배
    [0.95, 1], // 이미 큼 → 줄이지 않음
    [0.001, MAX_PLAYBACK_GAIN], // 거의 무음 → 최대 배율에서 멈춤
    [0, 1], // 완전 무음 → 그대로
  ])('가장 큰 순간 %f → %f배', (peak, expected) => {
    expect(Math.abs(playbackGain(peak) - expected)).toBeLessThan(1e-3)
  })

  it('키운 뒤 가장 큰 순간은 약 −1 dBFS', () => {
    expect(0.4 * playbackGain(0.4)).toBeCloseTo(PLAYBACK_PEAK, 12)
  })
})

describe('readingsInTake (녹음 묶음)', () => {
  it('소리 구간 안의 점만 남긴다 (요약·저장·다시 듣기가 같은 점을 쓰게)', () => {
    const readings = [0, 1, 2, 3, 4].map((time) => ({ time, frequency: 150 }))
    expect(readingsInTake(readings, 1, 3).map((r) => r.time)).toEqual([1, 2, 3])
  })
})
