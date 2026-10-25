import { describe, expect, it } from 'vitest'
import {
  frequencyAtPosition,
  graphRange,
  isBeyond,
  offsetBySemitones,
  position,
  semitones,
  ticks,
} from '../src/dsp/pitchScale'
import { range } from '../src/dsp/range'

// iOS VoicePracticeTests/PitchScaleTests.swift를 옮겼다.
describe('PitchScale (반음 눈금)', () => {
  const axis = range(70, 400)

  it('반음: 두 배는 12개, 반은 −12개, 반음 하나 옮기면 2^(1/12)배', () => {
    expect(Math.abs(semitones(110, 220) - 12)).toBeLessThan(1e-9)
    expect(Math.abs(semitones(220, 110) + 12)).toBeLessThan(1e-9)
    expect(Math.abs(offsetBySemitones(220, 12) - 440)).toBeLessThan(1e-9)
    expect(Math.abs(offsetBySemitones(200, 1) - 200 * Math.pow(2, 1 / 12))).toBeLessThan(1e-9)
  })

  it('위치: 아래 끝 0, 위 끝 1, 되돌리면 같은 Hz', () => {
    expect(Math.abs(position(70, axis))).toBeLessThan(1e-12)
    expect(Math.abs(position(400, axis) - 1)).toBeLessThan(1e-12)
    for (const frequency of [70, 95, 150, 222.5, 400]) {
      expect(Math.abs(frequencyAtPosition(position(frequency, axis), axis) - frequency)).toBeLessThan(1e-9)
    }
  })

  it('같은 반음 폭은 어느 높이에서든 같은 길이로 그려진다 (Hz 직선 눈금에서는 높은 쪽이 2.4배 넓었다)', () => {
    const length = (low: number, steps: number) => position(offsetBySemitones(low, steps), axis) - position(low, axis)
    expect(Math.abs(length(110, 4) - length(260, 4))).toBeLessThan(1e-12)
    expect(Math.abs(length(80, 1) - length(350, 1))).toBeLessThan(1e-12)
    const linearLength = (low: number, steps: number) => (offsetBySemitones(low, steps) - low) / (axis.upper - axis.lower)
    expect(linearLength(260, 4) / linearLength(110, 4)).toBeGreaterThan(2.3)
  })

  it('[높이] 그래프 세로축: 목표 범위 ±50 Hz, 분석 범위(70~400 Hz) 안으로, 목표가 없으면 전체', () => {
    expect(graphRange(range(135, 175))).toEqual(range(85, 225))
    expect(graphRange(range(90, 120))).toEqual(range(70, 170)) // 아래 끝에 붙인다
    expect(graphRange(range(330, 390))).toEqual(range(280, 400)) // 위 끝에 붙인다
    expect(graphRange(null)).toEqual(range(70, 400))
    // 좁아진 세로축에도 눈금이 3개 이상
    expect(ticks(graphRange(range(135, 175))).length).toBeGreaterThanOrEqual(3)
    expect(ticks(graphRange(range(210, 230))).length).toBeGreaterThanOrEqual(3)
    // [높이] 그래프는 눈금을 5개 이상 (좁아진 세로축에서 읽기 쉽게)
    expect(ticks(range(85, 225), 5)).toEqual([90, 100, 125, 150, 175, 200])
    expect(ticks(range(70, 400), 5)).toEqual([70, 100, 150, 200, 300, 400])
    // 같은 목표 범위를 반음으로 보면 전체 축(70~400 Hz)보다 크게 보인다
    expect(semitones(70, 400) / semitones(85, 225)).toBeGreaterThan(1.7)
  })

  it('눈금: 전체 범위는 70·100·150·200·300·400, 좁은 범위는 더 촘촘한 묶음에서 3개 이상', () => {
    expect(ticks(axis)).toEqual([70, 100, 150, 200, 300, 400])
    expect(ticks(range(125, 245))).toEqual([125, 150, 175, 200])
    const narrow = ticks(range(175, 240))
    expect(narrow.length).toBeGreaterThanOrEqual(3)
    expect(narrow.every((value) => value >= 175 && value <= 240)).toBe(true)
  })

  it('세로축 밖: 두 점이 모두 같은 쪽 밖일 때만 (끝에 붙인 점선으로 그릴 구간)', () => {
    const r = range(70, 170)
    expect(isBeyond(180, 190, r)).toBe(true) // 둘 다 위
    expect(isBeyond(60, 65, r)).toBe(true) // 둘 다 아래
    expect(isBeyond(160, 180, r)).toBe(false) // 하나는 안 → 끝까지 실선
    expect(isBeyond(60, 180, r)).toBe(false) // 위아래로 가로지름
    expect(isBeyond(170, 170, r)).toBe(false) // 끝 위는 안
  })
})
