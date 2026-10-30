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
import { PitchSummary } from '../src/dsp/pitchSummary'
import { range } from '../src/dsp/range'
import {
  dropText,
  PHRASE_END_TYPE_LABELS,
  phraseDetailLines,
  phraseGuidance,
  phraseHeadline,
  phraseNotes,
  phrasePitchLine,
  phraseRequestLines,
} from '../src/text/phraseEnding'

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

describe('구절별 문장 끝 분석: 글 (iOS와 같은 문장)', () => {
  /** 입력 파일에서 이름으로 고른 경우의 점·목표 범위·분석 */
  function analyzed(name: string) {
    const item = fixture.cases.find((c) => c.name === name)
    if (item === undefined) throw new Error(`${name} 경우가 없다`)
    const readings: PitchReading[] = item.readings.map(([time, frequency]) => ({ time: time ?? Number.NaN, frequency }))
    const target = item.target === null ? null : range(item.target[0], item.target[1])
    return { readings, target, analysis: analyzePhraseEndings(readings, target) }
  }

  it('4반음 하강 — 요약 한 줄, 숫자, 안내, 구절 한 줄', () => {
    const { analysis } = analyzed('4반음 하강')
    expect(phraseHeadline(analysis)).toBe('문장 끝 1개 중 1개가 3반음 넘게 내려갔어요')
    expect(phraseDetailLines(analysis)).toEqual([
      '평균 4.0반음 내려감',
      '바닥이 목표 하한(180 Hz) 아래로 내려간 끝: 1개',
      '목표 범위 밖 순간의 100%가 문장 끝 0.3초에 있어요 (문장 끝은 목소리의 25%)',
    ])
    expect(phraseGuidance(analysis)).toBe('끝이 내려가는 건 자연스러워요. 바닥이 목표 하한 아래로 내려가지 않게만 해 보세요.')
    const phrase = analysis.phrases[0]
    expect(PHRASE_END_TYPE_LABELS[phrase.endType]).toBe('내려감')
    expect(phrasePitchLine(phrase)).toBe('200 → 159 Hz')
    expect(dropText(phrase.endDropSemitones)).toBe('4.0반음 내려감')
    expect(phraseNotes(phrase)).toEqual(['바닥 159 Hz · 목표 하한 아래'])
  })

  it('상승·평평·긁힘·목표 없음·목소리 없음', () => {
    const rise = analyzed('질문형 상승').analysis
    expect(phraseHeadline(rise)).toBe('문장 끝 1개 중 3반음 넘게 내려간 곳은 없어요')
    expect(dropText(rise.phrases[0].endDropSemitones)).toBe('3.0반음 올라감')
    expect(PHRASE_END_TYPE_LABELS[rise.phrases[0].endType]).toBe('올라감')

    expect(dropText(analyzed('평평한 구절').analysis.phrases[0].endDropSemitones)).toBe('거의 그대로')

    const fry = analyzed('끝에 90 Hz 6점 연속 (긁히는 소리 가능성), 끊긴 2점씩은 아님').analysis
    expect(phraseDetailLines(fry)).toEqual([
      '평균 하강 거의 없음',
      '바닥이 목표 하한(150 Hz) 아래로 내려간 끝: 2개',
      '목표 범위 밖 순간의 100%가 문장 끝 0.3초에 있어요 (문장 끝은 목소리의 26%)',
      '끝이 긁혔을 수도 있는 곳: 1개 (높이를 잘못 읽었을 수도 있어요)',
    ])
    expect(phraseNotes(fry.phrases[0])).toEqual(['바닥 90 Hz · 목표 하한 아래', '긁혔을 수도 있어요'])

    const noTarget = analyzed('목표 범위 없음').analysis
    expect(phraseDetailLines(noTarget)).toEqual(['평균 4.0반음 내려감'])
    expect(phraseGuidance(noTarget)).toBe('끝이 내려가는 건 자연스러워요. 3반음 안쪽으로만 내려가게 해 보세요.')

    const silent = analyzed('목소리 없음').analysis
    expect(phraseHeadline(silent)).toBe('문장으로 나눌 만큼 목소리가 이어진 곳이 없어요')
    expect(phraseDetailLines(silent)).toEqual([])
    expect(phraseRequestLines(silent)).toEqual([])
  })

  it('요청문: 수치 아래에 문장 끝 요약을 빈 줄로 감싸 넣고, 목표가 없으면 목표 줄을 뺀다', () => {
    const { readings, target, analysis } = analyzed('4반음 하강')
    const summary = PitchSummary.fromReadings(readings, 2, target)
    expect(summary).not.toBeNull()
    if (summary === null) return
    const lines = [
      '문장 끝 (무성음 0.25초 이상에서 구절을 나누고, 구절마다 마지막 0.3초를 구절 전체와 비교)',
      '- 구절 수: 1개',
      '- 평균 하강 폭: 4.0반음 (구절 중앙값 → 마지막 0.3초 중앙값, +면 내려감)',
      '- 3반음 넘게 내려간 구절: 1개 (100%)',
      '- 끝 바닥(마지막 0.3초의 아래 10%)이 목표 하한 아래인 구절: 1개',
      '- 목표 범위 밖 순간 중 문장 끝 0.3초에 있던 비율: 100% (문장 끝은 목소리가 잡힌 시간의 25%)',
      '- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): 0개',
      '한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.',
    ]
    expect(phraseRequestLines(analysis)).toEqual(lines)

    const request = summary.feedbackRequest('방금 녹음', false, analysis)
    expect(request).toContain('목표 범위 안 비율 75%)\n\n' + lines.join('\n') + '\n\n녹음 파일은 보내지 않았어요.')

    // 구절이 없거나 분석이 없으면 예전 요청문 그대로
    const plain = summary.feedbackRequest('방금 녹음', false)
    expect(plain).toContain('목표 범위 안 비율 75%)\n\n녹음 파일은 보내지 않았어요.')
    expect(plain).not.toContain('문장 끝 (')
    expect(summary.feedbackRequest('방금 녹음', false, analyzed('목소리 없음').analysis)).toBe(plain)

    expect(phraseRequestLines(analyzed('목표 범위 없음').analysis)).toEqual([
      lines[0],
      lines[1],
      lines[2],
      lines[3],
      lines[6],
      '한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내인지로 봐 주세요.',
    ])
  })
})
