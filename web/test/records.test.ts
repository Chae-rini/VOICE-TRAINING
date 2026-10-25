import { describe, expect, it } from 'vitest'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { PitchSummary } from '../src/dsp/pitchSummary'
import { range } from '../src/dsp/range'
import {
  isBaselineRecord,
  isRecordingRecord,
  isSessionRecord,
  isVowelRecord,
  pitchNumbers,
  pitchSummaryOf,
  type RecordingRecord,
} from '../src/model/records'
import { loadSettings, saveValue, SettingKeys, type KeyValueStorage } from '../src/model/settingsStorage'
import { EMPTY_VOICE_SETTINGS } from '../src/model/voiceSettings'
import { PracticeSessionLog, sessionRecord } from '../src/practice/sessionLog'
import {
  EMPTY_RECORDS,
  encodeRecordsFile,
  mergeRecords,
  parseRecordsFile,
  recordingFileName,
  RECORDS_FILE,
  withRecord,
} from '../src/storage/archive'
import { openRecordFolder } from '../src/storage/openFolder'
import { MemoryFolder } from '../src/storage/recordFolder'

// iOS VoicePracticeTests/PracticeRecordTests.swift의 PracticeSessionLogTests를 옮기고, 웹 기록 파일(W7)을 더했다.

const start = new Date(1_800_000_000_000)
const at = (seconds: number) => new Date(start.getTime() + seconds * 1000)

/** `from` [s]부터 0.02초 간격의 피치 점 `count`개. null은 무음. */
function readings(from: number, count: number, frequency: (i: number) => number | null): PitchReading[] {
  return Array.from({ length: count }, (_, i) => ({ time: from + i * 0.02, frequency: frequency(i) }))
}

describe('PracticeSessionLog (연습 한 번의 기록)', () => {
  it('녹음 두 번을 하나로 모으고, 녹음 사이의 빈 시간은 목소리로 세지 않는다', () => {
    const log = new PracticeSessionLog(start, 'en')
    log.beginTake()
    log.add(readings(100, 300, () => 150)) // 6초 동안 150 Hz
    log.beginTake()
    log.add(readings(200, 300, () => 250)) // 100초 뒤 6초 동안 250 Hz

    const summary = log.finish(at(120), range(140, 160))!
    expect(summary.takeCount).toBe(2)
    expect(summary.language).toBe('en')
    expect(summary.startedAt).toBe(start)
    expect(summary.pitch.duration).toBe(120)
    expect(summary.pitch.voicedSeconds).toBeCloseTo(2 * 299 * 0.02, 9) // 첫 점은 앞 점이 없어 0
    expect(summary.pitch.median).toBeCloseTo(200, 9)
    expect(summary.pitch.p10).toBe(150)
    expect(summary.pitch.p90).toBe(250)
    expect(summary.pitch.target).toEqual(range(140, 160))
    expect(summary.pitch.inTargetFraction).toBe(0.5)
  })

  it('녹음 중에 잠깐 쉰 시간도 목소리로 세지 않는다 (점 사이가 0.1초 넘게 벌어지면 0.1초까지만)', () => {
    const log = new PracticeSessionLog(start, 'ko')
    log.beginTake()
    log.add([
      { time: 10.0, frequency: 200 },
      { time: 10.02, frequency: 200 },
      { time: 10.04, frequency: null },
      { time: 12.04, frequency: 200 }, // 무음 점 뒤 2초 만에 다시 목소리
    ])
    expect(log.voicedSeconds).toBeCloseTo(0.02 + 0.1, 9)
    expect(log.voiced).toHaveLength(3)
  })

  it('30초보다 짧은 연습이나 목소리가 5초보다 짧게 잡힌 연습은 남기지 않는다', () => {
    const log = new PracticeSessionLog(start, 'ko')
    log.beginTake()
    log.add(readings(0, 500, () => 200)) // 약 10초
    expect(log.finish(at(20), null)).toBeNull()
    expect(log.finish(at(30), null)).not.toBeNull()

    const quiet = new PracticeSessionLog(start, 'ko')
    quiet.beginTake()
    quiet.add(readings(0, 3000, (i) => (i < 200 ? 200 : null))) // 60초 중 4초만 목소리
    expect(quiet.finish(at(60), null)).toBeNull()
  })

  it('목표 범위를 정하지 않았으면 목표 범위 안 비율도 없다', () => {
    const log = new PracticeSessionLog(start, 'ja')
    log.beginTake()
    log.add(readings(0, 500, () => 180))
    const summary = log.finish(at(45), null)!
    expect(summary.pitch.target).toBeNull()
    expect(summary.pitch.inTargetFraction).toBeNull()
    expect(summary.takeCount).toBe(1)
  })

  it('녹음마다 요약을 녹음 순서대로 쌓고, 목소리가 안 잡힌 녹음은 빼며, 정지할 때 함께 넘긴다', () => {
    const log = new PracticeSessionLog(start, 'ko')
    // 녹음을 시작하기 전에 불리면 무시한다
    log.finishTake(readings(0, 10, () => 150), 1, null, start)
    expect(log.takes).toHaveLength(0)

    log.beginTake()
    const first = readings(0, 300, () => 150)
    log.add(first)
    log.finishTake(first, 6, range(140, 160), at(10))

    log.beginTake()
    const silent = readings(20, 300, () => null)
    log.add(silent)
    log.finishTake(silent, 6, range(140, 160), at(30))

    log.beginTake()
    const third = readings(40, 300, (i) => (i < 150 ? 170 : 190))
    log.add(third)
    log.finishTake(third, 6, range(180, 220), at(50))

    expect(log.takes.map((t) => t.round)).toEqual([1, 3])
    const summary = log.finish(at(60), range(180, 220))!
    expect(summary.takeCount).toBe(3)
    expect(summary.takes).toEqual(log.takes)
    const one = summary.takes[0]
    expect(one.endedAt).toEqual(at(10))
    expect(one.pitch.duration).toBe(6)
    expect(one.pitch.median).toBe(150)
    expect(one.pitch.target).toEqual(range(140, 160))
    expect(one.pitch.inTargetFraction).toBe(1)
    // 녹음마다 그 녹음을 마친 때의 목표 범위로 잰다
    expect(summary.takes[1].pitch.median).toBe(180)
    expect(summary.takes[1].pitch.inTargetFraction).toBe(0.5)
  })

  it('연습 기록 모양으로 바꾸면 날짜는 ISO 글자, 숫자는 그대로이고, 기록 파일에 쓰고 다시 읽어도 같다', () => {
    const log = new PracticeSessionLog(start, 'en')
    log.beginTake()
    const take = readings(0, 1000, () => 190)
    log.add(take)
    log.finishTake(take, 20, range(180, 220), at(25))
    const record = sessionRecord(log.finish(at(90), range(180, 220))!, 'id-1')
    expect(record).toMatchObject({ id: 'id-1', startedAt: start.toISOString(), endedAt: at(90).toISOString(), takeCount: 1, language: 'en' })
    expect(record.pitch).toMatchObject({ duration: 90, median: 190, target: range(180, 220), inTargetFraction: 1 })
    expect(record.takes).toEqual([{ round: 1, endedAt: at(25).toISOString(), pitch: expect.objectContaining({ duration: 20 }) }])
    expect(isSessionRecord(record)).toBe(true)

    const reread = parseRecordsFile(encodeRecordsFile(withRecord(EMPTY_RECORDS, 'sessions', record), start))
    expect(reread.ok && reread.value.sessions).toEqual([record])
  })
})

describe('기록 모양', () => {
  const pitch = new PitchSummary(60, 25, 182.4, 165, 201.2, range(160, 200), 0.72)
  const recording: RecordingRecord = {
    id: 'r1',
    recordedAt: start.toISOString(),
    title: '',
    memo: '발표 연습',
    fileName: 'Ullim-20270115-1000.wav',
    language: 'ja',
    pitch: pitchNumbers(pitch),
    f2Median: null,
  }

  it('피치 숫자는 요약으로 되돌려도 같다', () => {
    expect(pitchSummaryOf(pitchNumbers(pitch))).toEqual(pitch)
  })

  it('남긴 녹음·기준 이력·모음 이력을 알아보고, 모양이 다른 항목은 화면에 쓰지 않는다', () => {
    expect(isRecordingRecord(recording)).toBe(true)
    expect(isRecordingRecord({ ...recording, language: 'fr' })).toBe(false)
    expect(isRecordingRecord({ ...recording, id: undefined })).toBe(false)
    expect(isRecordingRecord({ ...recording, pitch: { ...recording.pitch, median: 'x' } })).toBe(false)

    expect(isBaselineRecord({ id: 'b', measuredAt: start.toISOString(), median: 150, low: 130, high: 170, f2: null })).toBe(true)
    expect(isBaselineRecord({ id: 'b', measuredAt: '어제', median: 150, low: 130, high: 170, f2: null })).toBe(false)

    const vowel = { id: 'v', vowel: '아', f1: 750, f2: 1300, f1Spread: range(740, 760), f2Spread: range(1280, 1330), isF1Uncertain: false, measuredAt: start.toISOString() }
    expect(isVowelRecord(vowel)).toBe(true)
    expect(isVowelRecord({ ...vowel, vowel: '애' })).toBe(false)
  })

  it('기록 파일의 모르는 항목은 지우지 않고 그대로 다시 쓴다 (더 새 앱이 더한 것 등)', () => {
    const records = { ...EMPTY_RECORDS, recordings: [recording, { id: 'x', future: true }] }
    const reread = parseRecordsFile(encodeRecordsFile(records, start))
    expect(reread.ok && reread.value.recordings).toEqual(records.recordings)
  })
})

describe('기록 합치기·파일 이름', () => {
  const a = { id: 'a' }
  const b = { id: 'b' }
  const c = { id: 'c' }

  it('기록을 목록 끝에 더하고, 다른 목록은 그대로 둔다', () => {
    const next = withRecord(EMPTY_RECORDS, 'vowelHistory', a)
    expect(next.vowelHistory).toEqual([a])
    expect(next.sessions).toBe(EMPTY_RECORDS.sessions)
  })

  it('합칠 때는 바탕 기록을 그대로 두고, 없는 id만 뒤에 더한다 (id 없는 항목은 더하지 않음)', () => {
    const base = { ...EMPTY_RECORDS, sessions: [a, b] }
    const extra = { ...EMPTY_RECORDS, sessions: [b, c, { no: 'id' }], recordings: [a] }
    const merged = mergeRecords(base, extra)
    expect(merged.sessions).toEqual([a, b, c])
    expect(merged.recordings).toEqual([a])
    expect(mergeRecords(base, base)).toEqual(base)
  })

  it('남긴 녹음 파일 이름: Ullim-날짜-시각(초까지).wav, 같은 이름이 있으면 -2, -3', () => {
    const date = new Date(2026, 9, 25, 20, 12, 5)
    expect(recordingFileName(date, new Set())).toBe('Ullim-20261025-201205.wav')
    expect(recordingFileName(date, new Set(['Ullim-20261025-201205.wav', 'Ullim-20261025-201205-2.wav']))).toBe(
      'Ullim-20261025-201205-3.wav',
    )
  })

  it('기록 폴더를 열 때 폴더를 고르기 전에 쌓인 기록을 기록 파일에 더하고, 새것이 없으면 다시 쓰지 않는다', async () => {
    const folder = new MemoryFolder()
    const original = encodeRecordsFile({ ...EMPTY_RECORDS, sessions: [a] }, new Date('2026-10-01T00:00:00Z'))
    await folder.write(RECORDS_FILE, original)

    const same = await openRecordFolder(folder, EMPTY_VOICE_SETTINGS, new Set(), { ...EMPTY_RECORDS, sessions: [a] })
    expect(same.ok && same.records.sessions).toEqual([a])
    expect(await (await folder.read(RECORDS_FILE))!.text()).toBe(original)

    const pending = { ...EMPTY_RECORDS, sessions: [b], vowelHistory: [c] }
    const merged = await openRecordFolder(folder, EMPTY_VOICE_SETTINGS, new Set(), pending)
    expect(merged.ok && merged.records).toMatchObject({ sessions: [a, b], vowelHistory: [c] })
    const written = parseRecordsFile(await (await folder.read(RECORDS_FILE))!.text())
    expect(written.ok && written.value).toMatchObject({ sessions: [a, b], vowelHistory: [c] })
  })
})

describe('말하는 언어 (화면 설정)', () => {
  it('처음에는 한국어, 고른 언어를 기억하고, 모르는 값은 한국어로 읽는다', () => {
    const data = new Map<string, string>()
    const storage: KeyValueStorage = {
      getItem: (key) => data.get(key) ?? null,
      setItem: (key, value) => void data.set(key, value),
      removeItem: (key) => void data.delete(key),
    }
    expect(loadSettings(storage).practiceLanguage).toBe('ko')
    saveValue(storage, SettingKeys.practiceLanguage, 'ja')
    expect(loadSettings(storage).practiceLanguage).toBe('ja')
    expect([...data.keys()]).toEqual(['ullim.practiceLanguage']) // iOS와 같은 키 이름
    saveValue(storage, SettingKeys.practiceLanguage, 'fr')
    expect(loadSettings(storage).practiceLanguage).toBe('ko')
  })
})
