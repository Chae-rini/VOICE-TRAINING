import { describe, expect, it } from 'vitest'
import { rootMeanSquare } from '../src/dsp/pitchDetector'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { offsetBySemitones } from '../src/dsp/pitchScale'
import { LevelMeter, ResonanceMeter } from '../src/dsp/voiceMeters'
import { sine } from './signals'

// iOS VoicePracticeTests/VoiceMetersTests.swift를 옮겼다. 저장(기준 F2·기록) 테스트는 저장을 옮길 때 함께 옮긴다.

/** 0.02초 간격의 점. `level` [dBFS], `f2` [Hz] (null이면 무음 — 목소리·포먼트 없음) */
function readings(
  start: number,
  seconds: number,
  { level = -30, f0 = 160, f1 = 600, f2 = 1500 as number | null } = {},
): PitchReading[] {
  return Array.from({ length: Math.trunc(seconds / 0.02) }, (_, index) => ({
    time: start + index * 0.02,
    frequency: f2 === null ? null : f0,
    formants:
      f2 === null ? null : { f1: { frequency: f1, bandwidth: 80 }, f2: { frequency: f2, bandwidth: 120 } },
    level,
  }))
}

describe('LevelMeter (음량)', () => {
  it('소리 크기: 20·log₁₀(RMS) dBFS, 무음은 바닥값', () => {
    expect(Math.abs(LevelMeter.dBFS(1))).toBeLessThan(1e-12)
    expect(Math.abs(LevelMeter.dBFS(0.1) + 20)).toBeLessThan(1e-9)
    expect(LevelMeter.dBFS(0)).toBe(LevelMeter.floor)
    // 실제 조각: 진폭 0.5 사인파의 RMS는 0.5/√2 → 약 −9 dBFS
    const frame = sine(200, 48_000, 2048, 0.5)
    expect(Math.abs(LevelMeter.dBFS(rootMeanSquare(frame)) - 20 * Math.log10(0.5 / Math.SQRT2))).toBeLessThan(0.1)
  })

  it('평활: 최근 0.3초를 세기로 평균한다 (dB로 평균하지 않는다)', () => {
    // 1초 동안 −40 dBFS, 그 뒤 0.3초 −20 dBFS → 지금은 −20 쪽만
    const quietThenLoud = [...readings(0, 1, { level: -40 }), ...readings(1, 0.3, { level: -20 })]
    const now = quietThenLoud[quietThenLoud.length - 1].time
    expect(Math.abs(LevelMeter.smoothedLevel(quietThenLoud, now)! + 20)).toBeLessThan(1e-9)

    // 0.3초 안에 −20과 −40이 반씩: 세기 평균 = 10·log₁₀((0.01 + 0.0001)/2) ≈ −22.97 (dB 평균이면 −30)
    const mixed = Array.from({ length: 14 }, (_, i) => ({ time: i * 0.02, frequency: 150, level: i % 2 === 0 ? -20 : -40 }))
    expect(Math.abs(LevelMeter.smoothedLevel(mixed, 0.26)! - 10 * Math.log10((0.01 + 0.0001) / 2))).toBeLessThan(1e-9)

    expect(LevelMeter.smoothedLevel([], 5)).toBeNull()
    expect(LevelMeter.position(-60)).toBe(0)
    expect(LevelMeter.position(-30)).toBe(0.5)
    expect(LevelMeter.position(5)).toBe(1)
  })

  it('아주 큰 소리가 3초 이어질 때만 안내한다 (짧게 크거나, 중간에 많이 작아지면 아님)', () => {
    expect(LevelMeter.isSustainedLoud(readings(0, 3.1, { level: -5 }), 3.08)).toBe(true)
    expect(LevelMeter.isSustainedLoud(readings(0, 2, { level: -5 }), 1.98)).toBe(false)

    // 3초 중 0.3초(10%) 숨 쉬는 틈은 봐준다
    const withBreath = [
      ...readings(0, 1.5, { level: -5 }),
      ...readings(1.5, 0.3, { level: -45 }),
      ...readings(1.8, 1.3, { level: -5 }),
    ]
    expect(LevelMeter.isSustainedLoud(withBreath, 3.08)).toBe(true)

    // 3초 중 1초(33%) 작으면 아니다
    const mostlyLoud = [
      ...readings(0, 1, { level: -5 }),
      ...readings(1, 1, { level: -30 }),
      ...readings(2, 1.1, { level: -5 }),
    ]
    expect(LevelMeter.isSustainedLoud(mostlyLoud, 3.08)).toBe(false)

    // 보통 크기
    expect(LevelMeter.isSustainedLoud(readings(0, 5, { level: -25 }), 4.98)).toBe(false)
  })
})

describe('ResonanceMeter (공명 밝기)', () => {
  it('F2 이동 중앙값: 최근 2.5초의 목소리만, 점이 20개보다 적거나 무음이 길면 보여 주지 않는다', () => {
    // 3초 동안 F2 1200 Hz(아), 이어서 3초 2300 Hz(이) → 지금은 2300
    const vowels = [...readings(0, 3, { f2: 1200 }), ...readings(3, 3, { f2: 2300 })]
    expect(ResonanceMeter.current(vowels, 5.98)!.f2).toBe(2300)
    // 바뀐 지 1초: 2.5초 창 안에 1200이 1.5초, 2300이 1초 → 중앙값은 1200 쪽
    expect(ResonanceMeter.current(vowels, 3.98)!.f2).toBe(1200)

    // 점 부족: 목소리 0.3초(15점)뿐
    expect(ResonanceMeter.current(readings(0, 0.3), 0.28)).toBeNull()
    // 무음 구간: 목소리가 끊긴 지 2.5초가 넘으면 없음
    const thenSilent = [...readings(0, 2), ...readings(2, 3, { f2: null })]
    expect(ResonanceMeter.current(thenSilent, 4.98)).toBeNull()
    // 무음이 섞여도 목소리 점이 충분하면 그 점들로
    const pauses = [...readings(0, 1, { f2: 1800 }), ...readings(1, 0.5, { f2: null }), ...readings(1.5, 1, { f2: 1800 })]
    expect(ResonanceMeter.current(pauses, 2.48)!.f2).toBe(1800)
  })

  it('목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있으면 불확실로 표시한다 (모음 지도와 같은 규칙)', () => {
    expect(ResonanceMeter.current(readings(0, 1, { f0: 150, f1: 300 }), 0.98)!.isUncertain).toBe(false)
    expect(ResonanceMeter.current(readings(0, 1, { f0: 250, f1: 400 }), 0.98)!.isUncertain).toBe(true)
  })

  it('기준 대비 위치: 기준이 가운데, 반음 6개 밝으면 오른쪽 끝, 넘으면 끝에 붙는다', () => {
    expect(ResonanceMeter.position(1500, 1500)).toBe(0.5)
    expect(Math.abs(ResonanceMeter.position(offsetBySemitones(1500, 6), 1500) - 1)).toBeLessThan(1e-12)
    expect(Math.abs(ResonanceMeter.position(offsetBySemitones(1500, -3), 1500) - 0.25)).toBeLessThan(1e-12)
    expect(ResonanceMeter.position(600, 1500)).toBe(0)
    // 반음 눈금이라 기준이 달라도 같은 비율이면 같은 위치
    expect(Math.abs(ResonanceMeter.position(1800, 1500) - ResonanceMeter.position(2400, 2000))).toBeLessThan(1e-12)
  })

  it('녹음 전체의 F2 중앙값: 목소리와 포먼트가 잡힌 점만, 20개보다 적으면 없음', () => {
    expect(ResonanceMeter.median(readings(0, 2, { f2: 1750 }))).toBe(1750)
    expect(ResonanceMeter.median(readings(0, 0.3, { f2: 1750 }))).toBeNull()
    expect(ResonanceMeter.median(readings(0, 2, { f2: null }))).toBeNull()
  })
})
