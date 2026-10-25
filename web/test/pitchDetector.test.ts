import { describe, expect, it } from 'vitest'
import { PitchDetector } from '../src/dsp/pitchDetector'
import { add, harmonic, noise, sine } from './signals'

// iOS VoicePracticeTests/PitchDetectorTests.swift를 옮겼다.
describe('PitchDetector (YIN)', () => {
  const tones = [44_100, 48_000].flatMap((sampleRate) =>
    [75, 120, 200, 350, 399].map((frequency) => ({ sampleRate, frequency })),
  )

  it.each(tones)('순음(사인파) $frequency Hz @ $sampleRate Hz를 0.5Hz 이내로 찾는다', ({ sampleRate, frequency }) => {
    const detector = new PitchDetector(sampleRate)
    const estimate = detector.detect(sine(frequency, sampleRate, detector.frameLength))
    expect(estimate).not.toBeNull()
    expect(Math.abs(estimate!.frequency - frequency)).toBeLessThan(0.5)
  })

  it('배음이 섞인 목소리 같은 소리에서 기본주파수를 찾는다 (옥타브 오류 없음)', () => {
    const detector = new PitchDetector(48_000)
    const estimate = detector.detect(harmonic(180, 48_000, detector.frameLength))
    expect(Math.abs(estimate!.frequency - 180)).toBeLessThan(0.5)
  })

  it('잡음이 조금 섞여도 기본주파수를 찾는다', () => {
    const detector = new PitchDetector(48_000)
    const frame = add(sine(200, 48_000, detector.frameLength), noise(detector.frameLength, 0.05, 42))
    expect(Math.abs(detector.detect(frame)!.frequency - 200)).toBeLessThan(1)
  })

  it('무음은 null', () => {
    const detector = new PitchDetector(48_000)
    expect(detector.detect(new Float32Array(detector.frameLength))).toBeNull()
  })

  it('아주 작은 소리(RMS가 기준 미만)는 null', () => {
    const detector = new PitchDetector(48_000)
    expect(detector.detect(sine(200, 48_000, detector.frameLength, 0.001))).toBeNull()
  })

  it('잡음만 있으면 null', () => {
    const detector = new PitchDetector(48_000)
    expect(detector.detect(noise(detector.frameLength, 0.3, 7))).toBeNull()
  })

  it.each([50, 500, 800])('70~400Hz 밖의 소리(%i Hz)는 반이나 두 배 주파수로 잘못 읽지 않고 null', (frequency) => {
    const detector = new PitchDetector(48_000)
    expect(detector.detect(sine(frequency, 48_000, detector.frameLength))).toBeNull()
  })

  it('창 길이: 48 kHz·44.1 kHz 모두 2048샘플 (점 간격은 그 절반)', () => {
    expect(new PitchDetector(48_000).frameLength).toBe(2048)
    expect(new PitchDetector(44_100).frameLength).toBe(2048)
  })

  it('창 길이가 맞지 않으면 알려 준다', () => {
    expect(() => new PitchDetector(48_000).detect(new Float32Array(100))).toThrow()
  })
})
