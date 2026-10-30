import { describe, expect, it } from 'vitest'
import { analyzePhraseEndings, PHRASE_ENDING_RULES, type PhraseEndingSummary } from '../src/dsp/phraseEnding'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { PitchSummary } from '../src/dsp/pitchSummary'
import { range } from '../src/dsp/range'
import {
  isRecordingRecord,
  isSessionRecord,
  phraseNumbers,
  phraseSummaryOf,
  pitchNumbers,
  readableRecords,
  type RecordingRecord,
  type SessionRecord,
} from '../src/model/records'
import {
  PracticeSessionLog,
  sessionFeedbackRequest,
  sessionRecord,
  sessionSummaryOf,
  takeRequestLine,
  type SessionSummary,
} from '../src/practice/sessionLog'
import { EMPTY_RECORDS, encodeRecordsFile, parseRecordsFile } from '../src/storage/archive'
import { combinedPhraseSummary, summaryHeadline, summaryShortPhrase } from '../src/text/phraseEnding'

// 문장 끝 숫자를 기록(연습 기록의 녹음마다·남긴 녹음)에 남기기 (2026-10-30, 2단계 웹).
// iOS VoicePracticeTests/PhraseEndingRecordTests.swift와 같은 숫자로 같은 글이 나오는지 본다 (한쪽을 고치면 다른 쪽도 고친다).

const start = new Date(1_800_000_000_000)
const at = (seconds: number) => new Date(start.getTime() + seconds * 1000)
const rules = PHRASE_ENDING_RULES

/** 목표 범위가 있던 녹음: 구절 11개 중 7개가 3반음 넘게 내려감, 평균 2.5반음 */
const withTarget: PhraseEndingSummary = {
  phraseCount: 11,
  meanEndDropSemitones: 2.5,
  fallingOrDroppingCount: 7,
  fallingOrDroppingFraction: 7 / 11,
  endBelowTargetCount: 3,
  possibleFryCount: 1,
  outOfTargetAtEndFraction: 0.7,
  endFrameShare: 0.2,
}
/** 목표 범위가 없던 녹음: 구절 5개 중 1개, 평균 0.5반음 */
const noTarget: PhraseEndingSummary = {
  phraseCount: 5,
  meanEndDropSemitones: 0.5,
  fallingOrDroppingCount: 1,
  fallingOrDroppingFraction: 0.2,
  endBelowTargetCount: null,
  possibleFryCount: 0,
  outOfTargetAtEndFraction: null,
  endFrameShare: 0.25,
}

/** 녹음 두 번(문장 끝 숫자 `phrases`)을 한 연습 기록으로. 두 녹음 모두 10초 동안 180 Hz */
function session(phrases: readonly (PhraseEndingSummary | undefined)[]): SessionSummary {
  const log = new PracticeSessionLog(start, 'ko')
  phrases.forEach((phrase, index) => {
    log.beginTake()
    const readings: PitchReading[] = Array.from({ length: 500 }, (_, i) => ({ time: index * 100 + i * 0.02, frequency: 180 }))
    log.add(readings)
    log.finishTake(readings, 10, range(170, 190), at((index + 1) * 40), phrase)
  })
  return log.finish(at(90), range(170, 190))!
}

/** 기록 파일에 쓰고 다시 읽는다 (폴더·앱 파일에 남는 모양 그대로) */
function reread(records: typeof EMPTY_RECORDS) {
  const parsed = parseRecordsFile(encodeRecordsFile(records, start))
  if (!parsed.ok) throw new Error(parsed.reason)
  return readableRecords(parsed.value)
}

describe('연습 기록의 문장 끝', () => {
  it('기록 파일에 쓰고 다시 읽어도 녹음마다의 문장 끝 숫자가 그대로다', () => {
    const { sessions } = reread({ ...EMPTY_RECORDS, sessions: [sessionRecord(session([withTarget, noTarget]), 'id')] })
    expect(sessionSummaryOf(sessions[0]).takes.map((take) => take.phraseEndings)).toEqual([withTarget, noTarget])
  })

  it('녹음 하나의 분석을 그대로 남긴다 (요약 카드와 같은 숫자)', () => {
    // 1초 말하고 0.5초 쉬고, 1초 동안 200 Hz에서 끝 0.3초만 160 Hz로 (3.9반음 내려감)
    const readings: PitchReading[] = [
      ...Array.from({ length: 50 }, (_, i) => ({ time: i * 0.02, frequency: 180 })),
      ...Array.from({ length: 25 }, (_, i) => ({ time: 1 + i * 0.02, frequency: null })),
      ...Array.from({ length: 50 }, (_, i) => ({ time: 1.5 + i * 0.02, frequency: i < 35 ? 200 : 160 })),
    ]
    const analysis = analyzePhraseEndings(readings, range(170, 210))
    expect(analysis.summary.phraseCount).toBe(2)
    const log = new PracticeSessionLog(start, 'ko')
    log.beginTake()
    log.finishTake(readings, 2.5, range(170, 210), at(10), analysis.summary)
    const record = sessionRecord({ ...session([undefined]), takes: log.takes }, 'id')
    expect(record.takes[0].phraseEndings).toEqual(phraseNumbers(analysis.summary))
  })

  it('그 전에 남긴 기록은 문장 끝 칸이 없어 숫자도, 요청문의 문장 끝 단락도 없다', () => {
    const old = { round: 1, endedAt: start, pitch: new PitchSummary(10, 8, 180, 170, 190, null, null) }
    expect(takeRequestLine(old, null)).not.toContain('문장 끝')
    const plain = session([undefined, undefined])
    expect(sessionFeedbackRequest(plain)).not.toContain('문장 끝')
    expect(sessionRecord(plain, 'id').takes.every((take) => !('phraseEndings' in take))).toBe(true)
  })

  it('망가진 문장 끝 칸은 숫자를 지어내지 않고 비우되, 연습 기록은 그대로 보인다', () => {
    expect(phraseSummaryOf(undefined)).toBeNull()
    expect(phraseSummaryOf({ phraseCount: 3, meanEndDropSemitones: 1, possibleFryCount: 0 })).toBeNull()
    expect(phraseSummaryOf({ ...phraseNumbers(withTarget), endFrameShare: 'x' })).toBeNull()

    const record = sessionRecord(session([withTarget]), 'id')
    // 손으로 고친 기록 파일처럼 구절 수 말고는 비어 있는 칸
    const broken = { ...record, takes: [{ ...record.takes[0], phraseEndings: { phraseCount: 3 } }] } as unknown as SessionRecord
    expect(isSessionRecord(broken)).toBe(true)
    expect(sessionSummaryOf(broken).takes[0].phraseEndings).toBeUndefined()
  })

  it('녹음 여러 개 합치기: 개수는 더하고 평균 하강 폭은 구절 수로 가중 평균, 합칠 수 없는 비율은 비운다', () => {
    const both = combinedPhraseSummary([withTarget, noTarget])!
    expect(both.phraseCount).toBe(16)
    expect(both.fallingOrDroppingCount).toBe(8)
    expect(both.fallingOrDroppingFraction).toBe(0.5)
    expect(both.meanEndDropSemitones).toBe((2.5 * 11 + 0.5 * 5) / 16)
    expect(both.endBelowTargetCount, '목표가 있던 녹음만 더한다').toBe(3)
    expect(both.possibleFryCount).toBe(1)
    expect(both.outOfTargetAtEndFraction).toBeNull()
    expect(both.endFrameShare).toBeNull()

    expect(combinedPhraseSummary([noTarget])?.endBelowTargetCount).toBeNull()
    expect(combinedPhraseSummary([])).toBeNull()
  })

  it('연습 기록 요청문: 녹음마다 줄에 문장 끝을 붙이고, 녹음 전체를 합친 문장 끝 단락을 녹음마다 아래에 넣는다', () => {
    const text = sessionFeedbackRequest(session([withTarget, noTarget]))
    expect(text).toContain('목표 범위 안 100%, 문장 끝 11개 중 7개 3반음 넘게 내려감, 평균 2.5반음 내려감\n')
    expect(text).toContain('목표 범위 안 100%, 문장 끝 5개 중 1개 3반음 넘게 내려감, 평균 0.5반음 내려감\n')
    const block = [
      '문장 끝 (녹음 2개를 합쳐서, 무성음 0.25초 이상에서 구절을 나누고, 구절마다 마지막 0.3초를 구절 전체와 비교)',
      '- 구절 수: 16개',
      '- 평균 하강 폭: 1.9반음 (구절 중앙값 → 마지막 0.3초 중앙값, +면 내려감)',
      '- 3반음 넘게 내려간 구절: 8개 (50%)',
      '- 끝 바닥(마지막 0.3초의 아래 10%)이 목표 하한 아래인 구절: 3개',
      '- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): 1개',
      '한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.',
    ].join('\n')
    expect(text).toContain('평균 0.5반음 내려감\n\n' + block + '\n\n녹음 파일은 보내지 않았어요.')
    expect(text, '녹음마다의 비율은 합칠 수 없어 넣지 않는다').not.toContain('목표 범위 밖 순간 중')

    // 문장 끝 숫자가 있는 녹음만 합치고, 몇 개를 합쳤는지 밝힌다
    const partial = sessionFeedbackRequest(session([undefined, withTarget]))
    expect(partial).toContain('문장 끝 (녹음 1개를 합쳐서,')
    expect(partial).toContain('- 구절 수: 11개')
  })
})

describe('남긴 녹음의 문장 끝', () => {
  const recording: RecordingRecord = {
    id: 'r',
    recordedAt: start.toISOString(),
    title: '',
    memo: '',
    fileName: 'Ullim-test.wav',
    language: 'ko',
    pitch: pitchNumbers(new PitchSummary(1, 1, 180, 179, 181, range(170, 190), 1)),
    f2Median: null,
  }

  it('남긴 녹음에 문장 끝 숫자를 남기고, 다시 읽어도 그대로다 (없이 남기면 비어 있다)', () => {
    const kept = { ...recording, phraseEndings: phraseNumbers(withTarget) }
    const { recordings } = reread({ ...EMPTY_RECORDS, recordings: [kept, { ...recording, id: 'plain' }] })
    expect(recordings.every(isRecordingRecord)).toBe(true)
    const byId = new Map(recordings.map((r) => [r.id, phraseSummaryOf(r.phraseEndings)]))
    expect(byId.get('r')).toEqual(withTarget)
    expect(byId.get('plain')).toBeNull()
  })

  it('메모·언어를 고쳐도 문장 끝 숫자가 남는다 (예전 앱처럼 모르는 칸이어도 펼쳐 쓴다)', () => {
    const kept = { ...recording, phraseEndings: phraseNumbers(withTarget) }
    const edited = { ...(kept as object), memo: '고친 메모' } as RecordingRecord
    expect(phraseSummaryOf(edited.phraseEndings)).toEqual(withTarget)
  })
})

describe('기록 화면의 한 줄 글', () => {
  it('요약 한 줄과 녹음마다 붙이는 짧은 말', () => {
    expect(summaryHeadline(withTarget, rules)).toBe('문장 끝 11개 중 7개가 3반음 넘게 내려갔어요')
    expect(summaryShortPhrase(withTarget, rules)).toBe('문장 끝 11개 중 7개 3반음 넘게 내려감, 평균 2.5반음 내려감')
    const none: PhraseEndingSummary = {
      phraseCount: 0,
      meanEndDropSemitones: null,
      fallingOrDroppingCount: 0,
      fallingOrDroppingFraction: null,
      endBelowTargetCount: null,
      possibleFryCount: 0,
      outOfTargetAtEndFraction: null,
      endFrameShare: null,
    }
    expect(summaryHeadline(none, rules)).toBe('문장으로 나눌 만큼 목소리가 이어진 곳이 없어요')
    expect(summaryShortPhrase(none, rules)).toBeNull()
  })
})
