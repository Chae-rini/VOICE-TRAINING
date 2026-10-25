import { describe, expect, it } from 'vitest'
import { complex, FormantAnalyzer, magnitude, subtract } from '../src/dsp/formantAnalyzer'
import { SplitMix64, SyntheticVowel } from './signals'

// iOS VoicePracticeTests/FormantAnalyzerTests.swift를 옮겼다.
describe('FormantAnalyzer (LPC)', () => {
  const sampleRate = 48_000 // [Hz]

  /** 합성 모음의 조각 9개에서 잰 F1·F2의 중앙값 [Hz] */
  function measure(formants: readonly number[], f0: number): { f1: number; f2: number } | null {
    const analyzer = new FormantAnalyzer(sampleRate)
    const signal = SyntheticVowel.make(formants, f0, sampleRate, 0.6)
    const estimates = SyntheticVowel.frames(signal, sampleRate).flatMap((frame) => {
      const estimate = analyzer.estimate(frame)
      return estimate === null ? [] : [estimate]
    })
    if (estimates.length < 5) return null
    const median = (values: number[]) => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
    return { f1: median(estimates.map((e) => e.f1.frequency)), f2: median(estimates.map((e) => e.f2.frequency)) }
  }

  it('48 kHz 소리는 12 kHz로 줄여 LPC 12차로 분석한다', () => {
    const analyzer = new FormantAnalyzer(48_000)
    expect(analyzer.decimationFactor).toBe(4)
    expect(analyzer.analysisRate).toBe(12_000)
    expect(analyzer.order).toBe(12)
  })

  it('Levinson–Durbin은 알려진 AR(2) 과정의 계수를 되찾는다', () => {
    // x[n] = 1.3·x[n−1] − 0.8·x[n−2] + e[n]  →  A(z) = 1 − 1.3z⁻¹ + 0.8z⁻²
    const generator = new SplitMix64(42)
    const x = new Array<number>(40_000).fill(0)
    for (let n = 2; n < x.length; n++) {
      x[n] = 1.3 * x[n - 1] - 0.8 * x[n - 2] + (generator.uniform() * 2 - 1)
    }
    const r = [0, 1, 2].map((k) => x.slice(0, x.length - k).reduce((sum, value, i) => sum + value * x[i + k], 0))
    const a = FormantAnalyzer.levinsonDurbin(r, 2)
    expect(a).not.toBeNull()
    expect(Math.abs(a![0] - -1.3)).toBeLessThan(0.03)
    expect(Math.abs(a![1] - 0.8)).toBeLessThan(0.03)
  })

  it('다항식의 근을 모두 찾는다: (z−0.5)(z+0.25)(z²−z+0.5)', () => {
    const roots = FormantAnalyzer.polynomialRoots([1, -1.25, 0.625, 0, -0.0625])
    expect(roots).toHaveLength(4)
    for (const expected of [complex(0.5, 0), complex(-0.25, 0), complex(0.5, 0.5), complex(0.5, -0.5)]) {
      expect(roots.some((root) => magnitude(subtract(root, expected)) < 1e-9)).toBe(true)
    }
  })

  it.each([100, 150])('목소리가 낮을 때(F0 %i Hz): 7개 모음의 F1·F2를 8% 안으로 잰다', (f0) => {
    for (const shape of SyntheticVowel.shapes) {
      const measured = measure(shape.formants, f0)
      expect(measured, shape.name).not.toBeNull()
      expect(Math.abs(measured!.f1 - shape.formants[0]) / shape.formants[0], `${shape.name} F1`).toBeLessThan(0.08)
      expect(Math.abs(measured!.f2 - shape.formants[1]) / shape.formants[1], `${shape.name} F2`).toBeLessThan(0.08)
    }
  })

  // F0 200 Hz 이상에서는 F1이 배음 쪽으로 끌려 최대 20~36% 틀린다 (LPC의 알려진 한계). 그래서 F2만 확인한다.
  it('F0 200 Hz: F2는 7개 모음 모두 5% 안으로 잰다', () => {
    for (const shape of SyntheticVowel.shapes) {
      const measured = measure(shape.formants, 200)
      expect(measured, shape.name).not.toBeNull()
      expect(Math.abs(measured!.f2 - shape.formants[1]) / shape.formants[1], `${shape.name} F2`).toBeLessThan(0.05)
    }
  })

  it('무음이나 너무 짧은 조각은 재지 않는다', () => {
    const analyzer = new FormantAnalyzer(sampleRate)
    expect(analyzer.estimate(new Float32Array(2048))).toBeNull()
    expect(analyzer.estimate(new Float32Array(40).fill(0.1))).toBeNull()
  })
})
