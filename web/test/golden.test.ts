import { afterAll, describe, expect, it } from 'vitest'
import { analyzeSamples } from '../src/dsp/analysis'
import { FormantAnalyzer } from '../src/dsp/formantAnalyzer'
import { PitchDetector } from '../src/dsp/pitchDetector'
import goldenJson from './golden/swift-golden.json'
import { add, glide, harmonic, noise, sine, SyntheticVowel } from './signals'

/**
 * iOS 앱과 같은 숫자가 나오는지: Tools/WebGolden(Swift)이 앱의 분석 코드로 만든 정답표와 비교한다.
 * 정답표를 다시 만드는 방법은 Tools/WebGolden/main.swift 맨 위에 있다.
 *
 * 목소리 있음/없음(null)은 하나도 달라서는 안 된다. 숫자는 갈래마다 가장 큰 차이를 모아 허용 오차와 비교한다.
 * 허용 오차가 0이 아닌 까닭: iOS는 합(Σ)을 vDSP(SIMD)로 더하고 표본 줄이기를 단정밀도(Float)로 계산해서,
 * 더하는 순서와 정밀도가 조금 다르다. 허용 오차는 그 차이만큼이고, 화면에 보이는 정밀도(1 Hz)보다 훨씬 작다.
 * 2026-10-25 처음 비교: 높이 최대 3e-12 Hz, F1·F2 최대 0.002 Hz, 소리 크기 최대 1e-6 dB.
 */

interface PitchResult {
  input: number
  sampleRate: number
  frequency?: number
  confidence?: number
}

interface Golden {
  sines: PitchResult[]
  harmonic: PitchResult
  noisyTone: PitchResult
  noiseOnly: PitchResult
  glide: {
    sampleRate: number
    from: number
    to: number
    seconds: number
    amplitude: number
    readings: { time: number; frequency?: number; level: number; f1?: number; f2?: number }[]
  }
  vowels: {
    name: string
    formants: number[]
    f0: number
    sampleRate: number
    frames: {
      frequency?: number
      f1?: number
      f1Bandwidth?: number
      f2?: number
      f2Bandwidth?: number
      candidates: number[][]
    }[]
  }[]
  intermediates: {
    lowPass48k: number[]
    hammingCount: number
    hamming: number[]
    decimated: number[]
    lpc: number[]
    roots: number[][]
  }
}

const golden = goldenJson as unknown as Golden

/** 갈래마다 허용하는 가장 큰 차이. `relative`는 정답값에 대한 비율. */
const TOLERANCES: Record<string, { limit: number; relative?: boolean }> = {
  '높이 [Hz]': { limit: 1e-6 },
  '확신도': { limit: 1e-9 },
  '소리 크기 [dB]': { limit: 1e-4 },
  'F1·F2 [Hz]': { limit: 0.01 },
  'F1·F2 대역폭 [Hz]': { limit: 0.05 },
  // 대역폭이 아주 넓은 후보(앱이 F1·F2로 쓰지 않는 것)는 근의 반지름이 작아 차이가 커 보인다 (2026-10-25 최대 8.8e-5)
  '포먼트 후보 (넓은 것 포함, 상대)': { limit: 1e-3, relative: true },
  '저역 통과 필터 (상대)': { limit: 2.5e-7, relative: true },
  'Hamming 창': { limit: 1e-12 },
  '표본 줄이기': { limit: 1e-6 },
  'LPC 계수': { limit: 1e-5 },
  '다항식의 근': { limit: 1e-12 },
}

/** 갈래마다 가장 큰 차이와 그 위치 */
const worst = new Map<string, { diff: number; label: string; count: number }>()

/** 둘 다 없거나(null), 둘 다 있으면 차이를 갈래에 모은다 */
function compare(category: string, actual: number | null | undefined, expected: number | undefined, label: string) {
  if (expected === undefined) {
    expect(actual ?? null, `${label}: iOS는 없음`).toBeNull()
    return
  }
  expect(actual ?? null, `${label}: iOS는 ${expected}`).not.toBeNull()
  const tolerance = TOLERANCES[category]
  const diff = Math.abs(actual! - expected) / (tolerance.relative ? Math.max(Math.abs(expected), 1e-12) : 1)
  const entry = worst.get(category) ?? { diff: 0, label: '', count: 0 }
  worst.set(category, diff > entry.diff ? { diff, label, count: entry.count + 1 } : { ...entry, count: entry.count + 1 })
}

function comparePitch(result: PitchResult, frame: Float32Array, label: string) {
  const estimate = new PitchDetector(result.sampleRate).detect(frame)
  compare('높이 [Hz]', estimate?.frequency, result.frequency, label)
  compare('확신도', estimate?.confidence, result.confidence, label)
}

describe('iOS 정답표와 비교 (Tools/WebGolden)', () => {
  it('사인파 16개 (44.1·48 kHz, 범위 밖 포함)', () => {
    expect(golden.sines).toHaveLength(16)
    for (const result of golden.sines) {
      const frameLength = new PitchDetector(result.sampleRate).frameLength
      comparePitch(result, sine(result.input, result.sampleRate, frameLength), `사인 ${result.input} Hz @ ${result.sampleRate}`)
    }
  })

  it('배음이 섞인 소리, 잡음 섞인 소리, 잡음만', () => {
    const frameLength = 2048
    comparePitch(golden.harmonic, harmonic(180, 48_000, frameLength), '배음 180 Hz')
    comparePitch(golden.noisyTone, add(sine(200, 48_000, frameLength), noise(frameLength, 0.05, 42)), '잡음 섞인 200 Hz')
    comparePitch(golden.noiseOnly, noise(frameLength, 0.3, 7), '잡음만')
  })

  it('높이가 오르는 소리 1.5초를 녹음 파일처럼 처음부터 끝까지 (점 시각·높이·크기·포먼트)', () => {
    const { sampleRate, from, to, seconds, amplitude, readings: expected } = golden.glide
    const actual = analyzeSamples(glide(from, to, seconds, sampleRate, amplitude), sampleRate)
    expect(actual).toHaveLength(expected.length)
    actual.forEach((reading, i) => {
      const label = `오르는 소리 ${i}번째 점`
      expect(reading.time).toBeCloseTo(expected[i].time, 12)
      compare('높이 [Hz]', reading.frequency, expected[i].frequency, label)
      compare('소리 크기 [dB]', reading.level, expected[i].level, label)
      compare('F1·F2 [Hz]', reading.formants?.f1.frequency, expected[i].f1, `${label} F1`)
      compare('F1·F2 [Hz]', reading.formants?.f2.frequency, expected[i].f2, `${label} F2`)
    })
  })

  it('합성 모음 29개 × 조각 9개: 높이, F1·F2와 대역폭, 포먼트 후보 전체', () => {
    expect(golden.vowels).toHaveLength(29)
    for (const vowel of golden.vowels) {
      const detector = new PitchDetector(vowel.sampleRate)
      const analyzer = new FormantAnalyzer(vowel.sampleRate)
      const frames = SyntheticVowel.frames(SyntheticVowel.make(vowel.formants, vowel.f0, vowel.sampleRate, 0.6), vowel.sampleRate)
      expect(frames).toHaveLength(vowel.frames.length)
      frames.forEach((frame, i) => {
        const label = `${vowel.name} F0 ${vowel.f0} @ ${vowel.sampleRate} 조각 ${i}`
        const expected = vowel.frames[i]
        compare('높이 [Hz]', detector.detect(frame)?.frequency, expected.frequency, label)
        const estimate = analyzer.estimate(frame)
        compare('F1·F2 [Hz]', estimate?.f1.frequency, expected.f1, `${label} F1`)
        compare('F1·F2 [Hz]', estimate?.f2.frequency, expected.f2, `${label} F2`)
        compare('F1·F2 대역폭 [Hz]', estimate?.f1.bandwidth, expected.f1Bandwidth, `${label} F1`)
        compare('F1·F2 대역폭 [Hz]', estimate?.f2.bandwidth, expected.f2Bandwidth, `${label} F2`)
        const candidates = analyzer.formants(frame) ?? []
        expect(candidates, `${label} 후보 수`).toHaveLength(expected.candidates.length)
        candidates.forEach((candidate, k) => {
          compare('포먼트 후보 (넓은 것 포함, 상대)', candidate.frequency, expected.candidates[k][0], `${label} 후보 ${k}`)
          compare('포먼트 후보 (넓은 것 포함, 상대)', candidate.bandwidth, expected.candidates[k][1], `${label} 후보 ${k} 폭`)
        })
      })
    }
  })

  it('중간 단계: 저역 통과 필터, Hamming 창, 표본 줄이기, LPC 계수, 다항식의 근', () => {
    const { lowPass48k, hammingCount, hamming, decimated, lpc, roots } = golden.intermediates

    const taps = FormantAnalyzer.lowPassFilter(5400, 48_000, 63) // 48 kHz: min(5500, 0.45·12000)
    expect(taps).toHaveLength(lowPass48k.length)
    taps.forEach((tap, i) => compare('저역 통과 필터 (상대)', tap, lowPass48k[i], `필터 ${i}`))

    FormantAnalyzer.hammingWindow(hammingCount).forEach((w, i) => compare('Hamming 창', w, hamming[i], `창 ${i}`))

    const frame = SyntheticVowel.frames(SyntheticVowel.make(SyntheticVowel.shapes[0].formants, 150, 48_000, 0.6), 48_000)[0]
    const down = FormantAnalyzer.downsample(frame, 4, taps)
    expect(down).toHaveLength(decimated.length)
    down.forEach((value, i) => compare('표본 줄이기', value, decimated[i], `표본 ${i}`))

    // LPC 계수: 정답표와 같은 단계를 거친다 (고역 강조 → Hamming 창 → 자기상관 → Levinson–Durbin)
    const x = Array.from(down, (value, n) => value - (n === 0 ? 0 : FormantAnalyzer.preEmphasis * down[n - 1]))
    const window = FormantAnalyzer.hammingWindow(x.length)
    const windowed = x.map((value, n) => value * window[n])
    const r = Array.from({ length: 13 }, (_, k) =>
      windowed.slice(0, windowed.length - k).reduce((sum, value, n) => sum + value * windowed[n + k], 0),
    )
    const a = FormantAnalyzer.levinsonDurbin(r, 12)!
    a.forEach((value, i) => compare('LPC 계수', value, lpc[i], `a${i + 1}`))

    FormantAnalyzer.polynomialRoots([1, -1.25, 0.625, 0, -0.0625]).forEach((root, i) => {
      compare('다항식의 근', root.re, roots[i][0], `근 ${i} 실수부`)
      compare('다항식의 근', root.im, roots[i][1], `근 ${i} 허수부`)
    })
  })

  afterAll(() => {
    const rows = Object.entries(TOLERANCES).map(([category, tolerance]) => {
      const entry = worst.get(category)
      return `  ${category}: 비교 ${entry?.count ?? 0}개, 가장 큰 차이 ${entry?.diff.toExponential(2) ?? '-'} (허용 ${tolerance.limit}) ${entry?.label ?? ''}`
    })
    console.info(`iOS 정답표와의 차이\n${rows.join('\n')}`)
  })

  it('갈래마다 가장 큰 차이가 허용 오차 안', () => {
    for (const [category, tolerance] of Object.entries(TOLERANCES)) {
      const entry = worst.get(category)
      expect(entry?.count ?? 0, `${category}: 비교한 값이 없음`).toBeGreaterThan(0)
      expect(entry!.diff, `${category}: ${entry!.label}`).toBeLessThan(tolerance.limit)
    }
  })
})
