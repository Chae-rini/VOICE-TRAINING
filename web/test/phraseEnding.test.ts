import { describe, expect, it } from 'vitest'
import rulesJson from '../../VoicePractice/Models/PhraseEndingRules.json'
import fixtureJson from '../../VoicePracticeTests/PhraseEndingCases.json'
import {
  analyzePhraseEndings,
  fryMinimumRun,
  PHRASE_ENDING_RULES,
  phraseEndType,
} from '../src/dsp/phraseEnding'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'

// iOS VoicePracticeTests/PhraseEndingAnalysisTests.swift와 같은 입력·기대값 파일(PhraseEndingCases.json)을 쓴다.
// 두 쪽이 같은 기대값을 통과하면 iOS와 웹이 같은 결과를 낸다는 뜻이다.
// 파일은 Tools/PhraseEndingCases/make_cases.py가 만들고, 기대값은 경우마다 손으로 셈한 값이다 (셈은 그 스크립트의 주석).

interface Fixture {
  readonly frameInterval: number
  readonly endTypeCases: readonly { readonly drop: number; readonly type: string }[]
  readonly fryRunCases: readonly { readonly frameInterval: number; readonly frames: number }[]
  readonly cases: readonly FixtureCase[]
}

interface FixtureCase {
  readonly name: string
  readonly target: readonly number[] | null
  /** [시각 s, Hz 또는 null] */
  readonly readings: readonly (readonly (number | null)[])[]
  readonly expected: {
    readonly phrases: readonly {
      readonly startTime: number
      readonly endTime: number
      readonly voicedFrameCount: number
      readonly endFrameCount: number
      readonly phraseMedian: number
      readonly endMedian: number
      readonly endFloor: number
      readonly endDropSemitones: number
      readonly endBelowTarget: boolean | null
      readonly endType: string
      readonly possibleFry: boolean
    }[]
    readonly summary: {
      readonly phraseCount: number
      readonly meanEndDropSemitones: number | null
      readonly fallingOrDroppingCount: number
      readonly fallingOrDroppingFraction: number | null
      readonly endBelowTargetCount: number | null
      readonly possibleFryCount: number
      readonly outOfTargetAtEndFraction: number | null
      readonly endFrameShare: number | null
    }
  }
}

const fixture: Fixture = fixtureJson

/** 두 값이 `tolerance` 안에서 같은지. 둘 다 null이어도 같다. */
function expectClose(actual: number | null, expected: number | null, label: string, tolerance = 1e-9) {
  if (expected === null) {
    expect(actual, label).toBeNull()
  } else {
    expect(actual, label).not.toBeNull()
    expect(Math.abs((actual ?? Number.NaN) - expected), label).toBeLessThanOrEqual(tolerance)
  }
}

describe('구절별 문장 끝 분석: 기준값', () => {
  it('기준값은 iOS와 같은 PhraseEndingRules.json 하나에서 온다', () => {
    expect(PHRASE_ENDING_RULES).toBe(rulesJson)
    expect(PHRASE_ENDING_RULES.endWindowSeconds).toBe(0.3)
    expect(PHRASE_ENDING_RULES.fryMinimumFrames).toBe(5)
  })

  it('종류: 하강 폭 경계값은 아래 종류에 든다 (≤ −2 rise, ≤ 3 stable, ≤ 5 falling)', () => {
    for (const item of fixture.endTypeCases) {
      expect(phraseEndType(item.drop, PHRASE_ENDING_RULES), `하강 ${item.drop}반음`).toBe(item.type)
    }
  })

  it('긁히는 소리 연속 기준: 10 ms × 5 = 50 ms를 점 간격으로 나눠 올림 (48 kHz → 3점)', () => {
    for (const item of fixture.fryRunCases) {
      expect(fryMinimumRun(PHRASE_ENDING_RULES, item.frameInterval), `간격 ${item.frameInterval} s`).toBe(item.frames)
    }
  })
})

describe('구절별 문장 끝 분석: 합성 피치 (iOS와 같은 입력·기대값)', () => {
  it('경우는 9가지', () => {
    expect(fixture.cases).toHaveLength(9)
  })

  it.each(fixture.cases)('$name', (item) => {
    const readings: PitchReading[] = item.readings.map(([time, frequency]) => ({ time: time ?? Number.NaN, frequency }))
    const target = item.target === null ? null : range(item.target[0], item.target[1])
    const analysis = analyzePhraseEndings(readings, target)
    const name = item.name

    expectClose(analysis.frameInterval, fixture.frameInterval, `${name}: 점 간격`, 1e-12)
    expect(analysis.phrases, `${name}: 구절 수`).toHaveLength(item.expected.phrases.length)
    item.expected.phrases.forEach((expected, index) => {
      const actual = analysis.phrases[index]
      const label = `${name} 구절 ${index + 1}`
      expectClose(actual.startTime, expected.startTime, `${label}: 시작`)
      expectClose(actual.endTime, expected.endTime, `${label}: 끝`)
      expect(actual.voicedFrameCount, `${label}: 유성 점 수`).toBe(expected.voicedFrameCount)
      expect(actual.endFrameCount, `${label}: 끝 점 수`).toBe(expected.endFrameCount)
      expectClose(actual.phraseMedian, expected.phraseMedian, `${label}: 구절 중앙값`)
      expectClose(actual.endMedian, expected.endMedian, `${label}: 끝 중앙값`)
      expectClose(actual.endFloor, expected.endFloor, `${label}: 끝 바닥`)
      expectClose(actual.endDropSemitones, expected.endDropSemitones, `${label}: 하강 폭`)
      expect(actual.endBelowTarget, `${label}: 목표 하한 아래`).toBe(expected.endBelowTarget)
      expect(actual.endType, `${label}: 종류`).toBe(expected.endType)
      expect(actual.possibleFry, `${label}: 긁히는 소리 가능성`).toBe(expected.possibleFry)
    })

    const summary = analysis.summary
    const expected = item.expected.summary
    expect(summary.phraseCount, `${name}: 요약 구절 수`).toBe(expected.phraseCount)
    expectClose(summary.meanEndDropSemitones, expected.meanEndDropSemitones, `${name}: 평균 하강`)
    expect(summary.fallingOrDroppingCount, `${name}: falling+dropping 수`).toBe(expected.fallingOrDroppingCount)
    expectClose(summary.fallingOrDroppingFraction, expected.fallingOrDroppingFraction, `${name}: falling+dropping 비율`)
    expect(summary.endBelowTargetCount, `${name}: 목표 하한 아래 구절 수`).toBe(expected.endBelowTargetCount)
    expect(summary.possibleFryCount, `${name}: 긁히는 소리 가능성 구절 수`).toBe(expected.possibleFryCount)
    expectClose(summary.outOfTargetAtEndFraction, expected.outOfTargetAtEndFraction, `${name}: 목표 밖 중 끝 비율`)
    expectClose(summary.endFrameShare, expected.endFrameShare, `${name}: 끝 점 비율`)
  })
})
