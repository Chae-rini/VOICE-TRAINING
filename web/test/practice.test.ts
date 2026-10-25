import { describe, expect, it } from 'vitest'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'
import { Baseline, PracticeDuration, TargetRange } from '../src/model/practice'
import { loadSettings, saveBaseline, saveTarget, saveValue, SettingKeys, type KeyValueStorage } from '../src/model/settingsStorage'

/** 0.02초 간격의 피치 기록. null은 무음. */
function readings(frequencies: (number | null)[]): PitchReading[] {
  return frequencies.map((frequency, i) => ({ time: i * 0.02, frequency }))
}

/** 테스트용 저장소 (브라우저 localStorage 대신) */
function memoryStorage(): KeyValueStorage & { data: Map<string, string> } {
  const data = new Map<string, string>()
  return {
    data,
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  }
}

// iOS VoicePracticeTests의 PracticeDurationTests·VoiceBaselineTests를 옮겼다.
describe('들려줄 길이', () => {
  it.each([
    [0, 10],
    [5, 10],
    [44, 40],
    [45, 50],
    [999, 180],
  ])('10초~3분 안으로 자르고 10초 단위로 맞춘다: %f → %f', (input, expected) => {
    expect(PracticeDuration.normalized(input)).toBe(expected)
  })

  it.each([
    [10, '10초'],
    [60, '1분'],
    [90, '1분 30초'],
    [180, '3분'],
  ])('시간 표시 문구: %f → %s', (seconds, expected) => {
    expect(PracticeDuration.label(seconds)).toBe(expected)
  })

  it('대본 길이에 맞춘 들려줄 길이: 예상 시간을 10초 단위로 올림 (끝까지 읽을 수 있게)', () => {
    expect(PracticeDuration.suggestedFor(23.6)).toBe(30)
    expect(PracticeDuration.suggestedFor(30)).toBe(30)
    expect(PracticeDuration.suggestedFor(4)).toBe(10)
  })
})

describe('내 기준 목소리', () => {
  it('중앙값과 아래·위 10% 지점을 잰다', () => {
    // 3초(150점) 동안 100~249 Hz가 고르게 잡힘
    const result = Baseline.measure(readings(Array.from({ length: 150 }, (_, i) => 100 + i)))
    expect(result.kind).toBe('measured')
    if (result.kind !== 'measured') return
    expect(Math.abs(result.baseline.median - 174.5)).toBeLessThan(1e-9)
    expect(Math.abs(result.baseline.low - 114.9)).toBeLessThan(1e-9)
    expect(Math.abs(result.baseline.high - 234.1)).toBeLessThan(1e-9)
    expect(result.baseline.f2).toBeNull() // 포먼트가 없는 기록
  })

  it('목소리가 2초보다 짧게 잡히면 다시 재자고 한다', () => {
    const oneSecond = Array.from({ length: 500 }, (_, i) => (i < 50 ? 200 : null)) // 10초 중 1초
    expect(Baseline.measure(readings(oneSecond)).kind).toBe('tooLittleVoice')
    expect(Baseline.measure(readings(new Array(500).fill(null))).kind).toBe('tooLittleVoice')
    expect(Baseline.measure([]).kind).toBe('tooLittleVoice')
    const enough = Array.from({ length: 500 }, (_, i) => (i < 110 ? 200 : null)) // 2.2초
    expect(Baseline.measure(readings(enough)).kind).toBe('measured')
  })

  it.each([
    [196.3, 175, 215],
    [150, 130, 170],
    [75, 70, 110], // 아래 끝: 70 Hz 아래로 내려가지 않게 민다
    [395, 360, 400], // 위 끝
  ])('처음 목표 범위는 기준 %f Hz ±20 Hz, 5 Hz 단위, 그래프 범위 안 → %f~%f', (median, lower, upper) => {
    expect(Baseline.initialTarget({ median, low: median - 10, high: median + 10, f2: null })).toEqual(range(lower, upper))
  })

  it('기준에서 ‘많이 떨어짐’은 반음 6개 기준이고, 위·아래 어느 쪽이든 똑같이 판단한다', () => {
    expect(Baseline.isFar(range(280, 320), 200)).toBe(true) // 가운데 300 Hz: 위로 약 7반음
    expect(Baseline.isFar(range(120, 140), 200)).toBe(true) // 가운데 130 Hz: 아래로 약 7.5반음
    expect(Baseline.isFar(range(230, 270), 200)).toBe(false) // 가운데 250 Hz: 위로 약 3.9반음
    expect(Baseline.isFar(range(180, 220), 200)).toBe(false)
  })
})

describe('목표 범위 슬라이더', () => {
  it('5 Hz 단위로 맞추고, 하한과 상한은 10 Hz 넘게 붙지 않는다', () => {
    const target = range(150, 200)
    expect(TargetRange.withLower(target, 163.2)).toEqual(range(165, 200))
    expect(TargetRange.withLower(target, 260)).toEqual(range(190, 200)) // 상한 − 10
    expect(TargetRange.withUpper(target, 211)).toEqual(range(150, 210))
    expect(TargetRange.withUpper(target, 100)).toEqual(range(150, 160)) // 하한 + 10
    expect(TargetRange.label(range(130, 320))).toBe('130 – 320 Hz')
  })
})

describe('설정 저장 (이 브라우저 안에만)', () => {
  it('처음에는 목표 범위·기준 없이, 들려줄 길이 1분, 내 문장, 전체 대본', () => {
    const settings = loadSettings(memoryStorage())
    expect(settings).toMatchObject({
      target: null,
      baseline: null,
      baselinePromptShown: false,
      practiceDuration: 60,
      sentenceSource: 'mine',
      scriptLength: 'any',
    })
    // 저장소를 쓸 수 없어도 기본값으로 동작한다
    expect(loadSettings(null).practiceDuration).toBe(60)
  })

  it('새로 쓰는 사람: 기준을 재면 목표 범위가 기준 ±20 Hz로 생긴다', () => {
    const storage = memoryStorage()
    const target = saveBaseline(storage, { median: 152, low: 130, high: 175, f2: 1600 }, true)
    expect(target).toEqual(range(130, 170))
    expect(loadSettings(storage)).toMatchObject({ target: range(130, 170), baseline: { median: 152, f2: 1600 } })
  })

  it('목표 범위를 맞추지 않으면 그대로 두고, F2를 못 잰 기준이면 예전 F2를 지운다', () => {
    const storage = memoryStorage()
    saveTarget(storage, range(180, 230))
    saveBaseline(storage, { median: 150, low: 130, high: 170, f2: 1500 }, false)
    saveBaseline(storage, { median: 155, low: 135, high: 175, f2: null }, false)
    const settings = loadSettings(storage)
    expect(settings.target).toEqual(range(180, 230))
    expect(settings.baseline).toEqual({ median: 155, low: 135, high: 175, f2: null })
  })

  it('잘못 저장된 값은 기본값으로 돌린다', () => {
    const storage = memoryStorage()
    saveValue(storage, SettingKeys.practiceDuration, 999)
    saveValue(storage, SettingKeys.sentenceSource, 'unknown')
    storage.setItem('ullim.targetLowerHz', 'abc')
    const settings = loadSettings(storage)
    expect(settings.practiceDuration).toBe(180)
    expect(settings.sentenceSource).toBe('mine')
    expect(settings.target).toBeNull()
  })

  it('키는 iOS와 같은 이름에 ‘ullim.’ 을 붙인다', () => {
    const storage = memoryStorage()
    saveTarget(storage, range(135, 175))
    expect([...storage.data.keys()].sort()).toEqual(['ullim.targetLowerHz', 'ullim.targetUpperHz'])
  })
})
