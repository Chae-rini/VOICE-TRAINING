import { describe, expect, it } from 'vitest'
import { analyzeSamples } from '../src/dsp/analysis'
import { StreamAnalyzer } from '../src/dsp/streamAnalyzer'
import { glide, SplitMix64, SyntheticVowel } from './signals'

/** 소리를 `sizes`를 돌려 가며 그 크기의 조각으로 잘라 넣는다 (마이크 조각 크기는 브라우저마다 다르다) */
function feed(analyzer: StreamAnalyzer, samples: Float32Array, sizes: number[], startTime = 0) {
  const readings = []
  let offset = 0
  for (let i = 0; offset < samples.length; i++) {
    const size = Math.min(sizes[i % sizes.length], samples.length - offset)
    readings.push(...analyzer.push(samples.subarray(offset, offset + size), startTime + offset / analyzer.sampleRate))
    offset += size
  }
  return readings
}

describe('StreamAnalyzer (마이크 조각 분석)', () => {
  const sampleRate = 48_000

  it('조각 크기가 어떻든 파일 분석(analyzeSamples)과 같은 점이 나온다', () => {
    // 오르는 소리 뒤에 합성 모음 ‘이’ — 높이·크기·포먼트가 모두 들어 있다
    const vowel = SyntheticVowel.make(SyntheticVowel.shapes[5].formants, 210, sampleRate, 0.6)
    const samples = new Float32Array(72_000 + vowel.length)
    samples.set(glide(120, 260, 1.5, sampleRate, 0.4))
    samples.set(vowel, 72_000)
    const expected = analyzeSamples(samples, sampleRate)

    const random = new SplitMix64(3)
    const randomSizes = Array.from({ length: 50 }, () => 1 + Math.floor(random.uniform() * 3000))
    for (const sizes of [[128], [1024], [4096], [37, 500, 2049], randomSizes]) {
      const actual = feed(new StreamAnalyzer(sampleRate), samples, sizes)
      expect(actual, `조각 ${sizes.slice(0, 3).join('·')}`).toHaveLength(expected.length)
      actual.forEach((reading, i) => {
        expect(reading.time).toBeCloseTo(expected[i].time, 9)
        expect(reading.frequency).toBe(expected[i].frequency)
        expect(reading.level).toBe(expected[i].level)
        expect(reading.formants).toEqual(expected[i].formants)
      })
    }
  })

  it('점의 시각은 소리 시계(첫 조각의 시각)를 따른다', () => {
    const analyzer = new StreamAnalyzer(sampleRate)
    const readings = feed(analyzer, glide(150, 150, 0.5, sampleRate, 0.4), [128], 100)
    expect(readings[0].time).toBeCloseTo(100 + 1024 / sampleRate, 9)
    expect(readings[1].time - readings[0].time).toBeCloseTo(1024 / sampleRate, 12)
  })

  it('44.1 kHz 마이크도 같은 방식 (창 2048, 점 간격 1024샘플)', () => {
    const analyzer = new StreamAnalyzer(44_100)
    expect(analyzer.frameLength).toBe(2048)
    expect(analyzer.hopLength).toBe(1024)
    const readings = feed(analyzer, glide(200, 200, 1, 44_100, 0.4), [128])
    expect(readings.every((r) => r.frequency !== null && Math.abs(r.frequency - 200) < 0.5)).toBe(true)
  })

  it('다시 시작하면(reset) 남은 소리를 버리고 새 조각의 시각부터 센다', () => {
    const analyzer = new StreamAnalyzer(sampleRate)
    analyzer.push(new Float32Array(1500), 0) // 창보다 짧아 점이 없다
    analyzer.reset()
    const readings = analyzer.push(new Float32Array(2048), 50)
    expect(readings).toHaveLength(1)
    expect(readings[0].time).toBeCloseTo(50 + 1024 / sampleRate, 9)
  })
})
