import { describe, expect, it } from 'vitest'
import { analyzeSamples } from '../src/dsp/analysis'
import { PitchHistory, type PitchReading } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'
import { comparisonText, signedHz, vowelChartDescription, vowelPlotRect } from '../src/graph/vowelChart'
import { isF1Uncertain, VowelSpace } from '../src/dsp/vowelSpace'
import { loadLegacyVoiceSettings, loadSettings, saveValue, SettingKeys, type KeyValueStorage } from '../src/model/settingsStorage'
import { VowelMaps } from '../src/model/vowelMap'
import { SyntheticVowel } from './signals'

// iOS VoicePracticeTests/VowelSpaceTests.swift·VowelMapTests.swift를 옮겼다.

function reading(time: number, f0: number | null, f1: number, f2: number): PitchReading {
  return { time, frequency: f0, formants: { f1: { frequency: f1, bandwidth: 80 }, f2: { frequency: f2, bandwidth: 100 } } }
}

/** 0.02초 간격의 기록. `hasFormants`가 false인 점은 포먼트 없이(목소리만) 남긴다. */
function readings(
  count: number,
  f0: number,
  f1: (i: number) => number,
  f2: (i: number) => number,
  hasFormants: (i: number) => boolean = () => true,
): PitchReading[] {
  return Array.from({ length: count }, (_, i) =>
    hasFormants(i) ? reading(i * 0.02, f0, f1(i), f2(i)) : { time: i * 0.02, frequency: f0, formants: null },
  )
}

const date = new Date(1_800_000_000_000)

describe('VowelSpace (모음 지도의 규칙)', () => {
  it.each([
    [300, 150, false], // 목소리가 낮으면 믿는다
    [380, 200, true], // 2×F0 근처로 끌렸을 수 있음
    [800, 200, false], // F1이 충분히 높음
    [600, 300, true],
    [800, 300, false],
  ])('F1 불확실 표시: F1 %d Hz, F0 %d Hz → %s', (f1, f0, expected) => {
    expect(isF1Uncertain(f1, f0)).toBe(expected)
  })

  it('지도 방향: F2가 높을수록 왼쪽(혀 앞쪽), F1이 높을수록 아래(입 크게), 범위 밖은 가장자리에', () => {
    expect(VowelSpace.position(200, 3000)).toEqual({ x: 0, y: 0 })
    expect(VowelSpace.position(1100, 600)).toEqual({ x: 1, y: 1 })
    expect(VowelSpace.position(500, 2300).x).toBeLessThan(VowelSpace.position(500, 900).x)
    expect(VowelSpace.position(800, 1300).y).toBeGreaterThan(VowelSpace.position(300, 1300).y)
    expect(VowelSpace.position(50, 5000)).toEqual({ x: 0, y: 0 })
  })

  it('지금 점은 최근 점들의 중앙값이고, 포먼트가 잡힌 점이 3개 미만이면 보여 주지 않는다', () => {
    const recent = [
      reading(0.0, 120, 500, 1500),
      reading(0.02, 120, 520, 1550),
      reading(0.04, 120, 900, 2500), // 튀는 값은 중앙값에서 빠진다
      { time: 0.06, frequency: null },
      reading(0.08, 120, 510, 1520),
    ]
    expect(VowelSpace.current(recent)).toEqual({ f1: 515, f2: 1535, isF1Uncertain: false })
    expect(VowelSpace.current(recent.slice(0, 2))).toBeNull()
  })

  it('목소리가 높고 F1이 낮으면 지금 점의 F1을 불확실로 표시한다', () => {
    const high = [0, 1, 2, 3].map((i) => reading(i * 0.02, 220, 420, 2300))
    expect(VowelSpace.current(high)?.isF1Uncertain).toBe(true)
  })

  it('기록에서 시간 구간의 점만 꺼낸다 (양 끝 포함)', () => {
    const history = new PitchHistory(100)
    history.append(Array.from({ length: 10 }, (_, i) => ({ time: i, frequency: 200 })))
    const times = (lower: number, upper: number) => history.readingsIn(range(lower, upper)).map((r) => r.time)
    expect(times(2, 5)).toEqual([2, 3, 4, 5])
    expect(times(2.5, 2.9)).toEqual([])
    expect(times(-5, 0)).toEqual([0])
    expect(times(9, 20)).toEqual([9])
  })

  it("녹음 파일을 분석하면 피치와 함께 포먼트도 담긴다 (합성 '아', F0 120 Hz)", () => {
    const sampleRate = 48_000
    const shape = SyntheticVowel.shapes[0] // 아: F1 800, F2 1300
    const fileReadings = analyzeSamples(SyntheticVowel.make(shape.formants, 120, sampleRate, 1), sampleRate)
    expect(fileReadings.filter((r) => r.formants).length).toBeGreaterThan(fileReadings.length / 2)

    const point = VowelSpace.current(fileReadings.filter((r) => r.time > 0.2))
    expect(point).not.toBeNull()
    expect(Math.abs(point!.f1 - 800) / 800).toBeLessThan(0.08)
    expect(Math.abs(point!.f2 - 1300) / 1300).toBeLessThan(0.08)
  })
})

describe('VowelMaps (내 모음 지도)', () => {
  it('모음 하나: 중앙값과 길게 내는 동안 흔들린 범위(25%~75%)를 잰다', () => {
    // 2초(100점). F1은 500~540, F2는 1500~1580에서 고르게 흔들림
    const entry = VowelMaps.measure(
      readings(100, 130, (i) => 500 + (i % 5) * 10, (i) => 1500 + (i % 5) * 20),
      date,
    )
    expect(entry).toEqual({
      f1: 520,
      f2: 1540,
      f1Spread: { lower: 510, upper: 530 },
      f2Spread: { lower: 1520, upper: 1560 },
      isF1Uncertain: false,
      measuredAt: date.toISOString(),
    })
  })

  it('포먼트가 1초보다 짧게 잡히면 저장하지 않는다', () => {
    // 3초(150점) 중 포먼트가 잡힌 것은 0.8초(40점)
    const short = readings(150, 130, () => 500, () => 1500, (i) => i < 40)
    expect(VowelMaps.measure(short)).toBeNull()
    expect(VowelMaps.measure([])).toBeNull()
  })

  it('목소리가 높고 F1이 낮으면 잰 값도 F1 불확실로 남긴다', () => {
    expect(VowelMaps.measure(readings(100, 230, () => 420, () => 2300))?.isF1Uncertain).toBe(true)
  })

  it('저장했다 다시 읽으면 같고, 같은 모음을 다시 재면 바뀌며, 망가진 값은 빈 지도로 읽는다', () => {
    const first = VowelMaps.measure(readings(100, 130, () => 800, () => 1300), date)!
    const second = VowelMaps.measure(readings(100, 130, () => 760, () => 1250), date)!

    let map = VowelMaps.withEntry({}, '아', first)
    expect(VowelMaps.measuredCount(map)).toBe(1)
    expect(VowelMaps.parse(JSON.stringify(map))).toEqual(map)

    map = VowelMaps.withEntry(map, '아', second)
    expect(map['아']).toEqual(second)
    expect(VowelMaps.measuredCount(map)).toBe(1)
    expect(map['이']).toBeUndefined()

    expect(VowelMaps.measuredCount(VowelMaps.parse('망가진 값'))).toBe(0)
    expect(VowelMaps.measuredCount(VowelMaps.parse(null))).toBe(0)
    // 모르는 모음과 숫자가 빠진 항목은 빼고 읽는다
    const partlyBroken = JSON.stringify({ 아: first, 애: first, 이: { ...first, f1: 'x' } })
    expect(VowelMaps.parse(partlyBroken)).toEqual({ 아: first })
  })

  it("녹음 파일로 모음 하나를 잰다 (합성 '이', F0 120 Hz)", () => {
    const sampleRate = 48_000
    const shape = SyntheticVowel.shapes.find((s) => s.name === '이')! // F1 300, F2 2300
    const entry = VowelMaps.measure(analyzeSamples(SyntheticVowel.make(shape.formants, 120, sampleRate, 2), sampleRate))
    expect(entry).not.toBeNull()
    expect(Math.abs(entry!.f1 - 300) / 300).toBeLessThan(0.08)
    expect(Math.abs(entry!.f2 - 2300) / 2300).toBeLessThan(0.08)
    expect(entry!.isF1Uncertain).toBe(false)
  })

  it('브라우저 저장소: 고른 모음을 저장했다 다시 읽고(모르는 모음은 ‘아’), W5에 둔 모음 지도는 옮기려고 읽는다', () => {
    const data = new Map<string, string>()
    const storage: KeyValueStorage = {
      getItem: (key) => data.get(key) ?? null,
      setItem: (key, value) => void data.set(key, value),
      removeItem: (key) => void data.delete(key),
    }
    expect(loadSettings(storage).selectedVowel).toBe('아')

    const entry = VowelMaps.measure(readings(100, 130, () => 300, () => 2300), date)!
    storage.setItem('ullim.vowelMap', JSON.stringify({ 이: entry }))
    saveValue(storage, SettingKeys.selectedVowel, '이')
    expect(loadLegacyVoiceSettings(storage)?.vowelMap).toEqual({ 이: entry })
    expect(loadSettings(storage).selectedVowel).toBe('이')

    saveValue(storage, SettingKeys.selectedVowel, '애')
    expect(loadSettings(storage).selectedVowel).toBe('아')
  })
})

describe('모음 지도 글자', () => {
  const entry = VowelMaps.measure(readings(100, 130, () => 800, () => 1300), date)!

  it('왼쪽 44·위 24는 눈금 자리, 아래 40은 F2 숫자와 방향 안내 자리 (iOS와 같다)', () => {
    expect(vowelPlotRect(343, 320)).toEqual({ x: 44, y: 24, width: 287, height: 256 })
  })

  it('차이는 부호와 함께 반올림해서 쓴다', () => {
    expect(signedHz(12.4)).toBe('+12')
    expect(signedHz(-30.6)).toBe('-31')
    expect(signedHz(-0.2)).toBe('0')
  })

  it('고른 모음을 쟀을 때만 지금 소리와의 차이를 보여 준다', () => {
    const current = { f1: 812, f2: 1270, isF1Uncertain: false }
    expect(comparisonText(current, { 아: entry }, '아')).toBe('내 ‘아’와 비교 · F1 +12 · F2 -30 Hz')
    expect(comparisonText(current, { 아: entry }, '이')).toBeNull()
    expect(comparisonText(null, { 아: entry }, '아')).toBeNull()
  })

  it('화면 읽기 설명: 지금 점과 내가 잰 모음들의 숫자', () => {
    expect(vowelChartDescription(null, {})).toBe('지금 잡힌 모음이 없어요.')
    expect(vowelChartDescription({ f1: 420, f2: 2300, isF1Uncertain: true }, { 아: entry })).toBe(
      '지금 F1 420 Hz, F2 2300 Hz, F1은 정확하지 않을 수 있어요. 내 모음 지도 1개: 아 F1 800, F2 1300 Hz.',
    )
  })
})
