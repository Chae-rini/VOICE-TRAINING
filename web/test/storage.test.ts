import { zipSync } from 'fflate'
import { describe, expect, it } from 'vitest'
import { range } from '../src/dsp/range'
import { EMPTY_VOICE_SETTINGS, mergeVoiceSettings, sameVoiceSettings, type VoiceSettings } from '../src/model/voiceSettings'
import type { VowelEntry } from '../src/model/vowelMap'
import {
  EMPTY_RECORDS,
  encodeRecordsFile,
  encodeSettingsFile,
  parseRecordsFile,
  parseSettingsFile,
  RECORDS_FILE,
  SETTINGS_FILE,
} from '../src/storage/archive'
import { copyRecordFolder, openRecordFolder } from '../src/storage/openFolder'
import { MemoryFolder, splitPath, type RecordFolder } from '../src/storage/recordFolder'
import { isRecordingName, packRecordFolder, recordFileName, unpackRecordFile } from '../src/storage/recordZip'

// W6 내 기록 폴더: 파일 모양, 폴더 열기(합치기·옮기기), 기록 파일(zip). 실제 폴더 대신 메모리 폴더로 시험한다.

const now = new Date('2026-10-25T11:00:00Z')

function vowel(f1: number, f2: number, measuredAt: string): VowelEntry {
  return { f1, f2, f1Spread: range(f1 - 10, f1 + 10), f2Spread: range(f2 - 20, f2 + 20), isF1Uncertain: false, measuredAt }
}

const mine: VoiceSettings = {
  target: range(140, 180),
  baseline: { median: 152, low: 130, high: 175, f2: 1600 },
  vowelMap: { 아: vowel(800, 1300, '2026-10-20T10:00:00.000Z') },
}

async function text(folder: RecordFolder, path: string): Promise<string | null> {
  return (await (await folder.read(path))?.text()) ?? null
}

describe('파일 모양', () => {
  it('설정 파일: 쓰고 다시 읽으면 같고, 사람이 읽을 수 있게 들여 쓴 JSON이다', () => {
    const encoded = encodeSettingsFile(mine, now)
    expect(parseSettingsFile(encoded)).toEqual({ ok: true, value: mine })
    expect(encoded).toContain('\n  "app": "ullim"')
    expect(JSON.parse(encoded)).toMatchObject({ kind: 'settings', version: 1, savedAt: '2026-10-25T11:00:00.000Z' })
  })

  it('기록 파일: 항목은 읽은 그대로 다시 쓴다 (모양은 W7에서 정한다), 없는 목록은 빈 목록', () => {
    const records = { ...EMPTY_RECORDS, sessions: [{ any: 'thing' }] }
    expect(parseRecordsFile(encodeRecordsFile(records, now))).toEqual({ ok: true, value: records })
    expect(parseRecordsFile('{"app":"ullim","kind":"records","version":1}')).toEqual({ ok: true, value: EMPTY_RECORDS })
  })

  it.each([
    ['망가진 JSON', '{"app":', 'broken'],
    ['다른 앱의 파일', '{"app":"other","kind":"settings","version":1}', 'notUllim'],
    ['기록 파일을 설정 자리에', '{"app":"ullim","kind":"records","version":1}', 'notUllim'],
    ['더 새 판', '{"app":"ullim","kind":"settings","version":2}', 'newerVersion'],
    ['판 번호 없음', '{"app":"ullim","kind":"settings"}', 'broken'],
    ['목표 범위가 거꾸로', '{"app":"ullim","kind":"settings","version":1,"target":{"lower":200,"upper":100}}', 'broken'],
    ['기준에 숫자가 아닌 값', '{"app":"ullim","kind":"settings","version":1,"baseline":{"median":"x","low":1,"high":2,"f2":null}}', 'broken'],
  ])('설정 파일을 읽지 못하는 경우: %s', (_, json, reason) => {
    expect(parseSettingsFile(json)).toEqual({ ok: false, reason })
  })

  it('모음 지도의 망가진 모음 하나는 빼고 나머지는 읽는다', () => {
    const json = JSON.stringify({ app: 'ullim', kind: 'settings', version: 1, vowelMap: { 아: mine.vowelMap['아'], 이: { f1: 'x' } } })
    expect(parseSettingsFile(json)).toEqual({ ok: true, value: { target: null, baseline: null, vowelMap: { 아: mine.vowelMap['아'] } } })
  })

  it('기록 폴더 경로는 한 단계 폴더까지, `..`·빈 이름은 막는다', () => {
    expect(splitPath(SETTINGS_FILE)).toEqual([null, SETTINGS_FILE])
    expect(splitPath('녹음/Ullim-20261025-2012.wav')).toEqual(['녹음', 'Ullim-20261025-2012.wav'])
    for (const bad of ['../a.json', '녹음/../a.wav', 'a/b/c.wav', '/a.json', '녹음/', '']) {
      expect(() => splitPath(bad)).toThrow()
    }
  })
})

describe('합치기 (기록 폴더를 열 때)', () => {
  const folderValues: VoiceSettings = {
    target: range(200, 240),
    baseline: null,
    vowelMap: { 아: vowel(780, 1280, '2026-10-24T10:00:00.000Z'), 이: vowel(300, 2300, '2026-10-21T10:00:00.000Z') },
  }

  it('폴더 값을 쓰되, 폴더에 없는 값은 화면 값을 쓰고, 모음은 모음마다 나중에 잰 값', () => {
    const merged = mergeVoiceSettings(folderValues, mine, new Set())
    expect(merged.target).toEqual(range(200, 240))
    expect(merged.baseline).toEqual(mine.baseline)
    expect(merged.vowelMap['아']?.f1).toBe(780) // 폴더 쪽이 나중에 잼 (24일 > 20일)
    expect(merged.vowelMap['이']?.f1).toBe(300)
  })

  it('다시 연결하기 전에 화면에서 바꾼 값은 화면 값을 남긴다', () => {
    expect(mergeVoiceSettings(folderValues, mine, new Set(['target'])).target).toEqual(range(140, 180))
  })

  it('키 순서만 다른 같은 값은 같다고 본다', () => {
    const reordered: VoiceSettings = {
      vowelMap: { ...mine.vowelMap },
      baseline: { f2: 1600, high: 175, low: 130, median: 152 },
      target: { upper: 180, lower: 140 },
    }
    expect(sameVoiceSettings(mine, reordered)).toBe(true)
    expect(sameVoiceSettings(mine, { ...mine, target: range(140, 185) })).toBe(false)
  })
})

describe('기록 폴더 열기', () => {
  it('빈 폴더: 화면 값(예전에 브라우저에 있던 값)으로 설정 파일과 빈 기록 파일을 만든다', async () => {
    const folder = new MemoryFolder()
    const result = await openRecordFolder(folder, mine, new Set(), undefined, now)
    expect(result).toEqual({ ok: true, settings: mine, records: EMPTY_RECORDS })
    expect(parseSettingsFile((await text(folder, SETTINGS_FILE))!)).toEqual({ ok: true, value: mine })
    expect(parseRecordsFile((await text(folder, RECORDS_FILE))!)).toEqual({ ok: true, value: EMPTY_RECORDS })
  })

  it('이미 쓰던 폴더: 폴더 값을 읽고, 합친 값이 같으면 파일을 다시 쓰지 않는다', async () => {
    const folder = new MemoryFolder()
    const original = encodeSettingsFile(mine, new Date('2026-10-01T00:00:00Z'))
    await folder.write(SETTINGS_FILE, original)
    await folder.write(RECORDS_FILE, encodeRecordsFile({ ...EMPTY_RECORDS, sessions: [1] }, now))
    const result = await openRecordFolder(folder, EMPTY_VOICE_SETTINGS, new Set(), undefined, now)
    expect(result).toEqual({ ok: true, settings: mine, records: { ...EMPTY_RECORDS, sessions: [1] } })
    expect(await text(folder, SETTINGS_FILE)).toBe(original)
  })

  it('합친 값이 폴더와 다르면 설정 파일을 고쳐 쓴다', async () => {
    const folder = new MemoryFolder()
    await folder.write(SETTINGS_FILE, encodeSettingsFile(EMPTY_VOICE_SETTINGS, now))
    await openRecordFolder(folder, mine, new Set(), undefined, now)
    expect(parseSettingsFile((await text(folder, SETTINGS_FILE))!)).toEqual({ ok: true, value: mine })
  })

  it('읽지 못한 파일이 있으면 아무것도 쓰지 않고 까닭을 알린다 (내 기록을 덮어쓰지 않게)', async () => {
    const folder = new MemoryFolder()
    await folder.write(SETTINGS_FILE, '{ 망가진')
    const result = await openRecordFolder(folder, mine, new Set(), undefined, now)
    expect(result.ok).toBe(false)
    expect(!result.ok && result.message).toContain('울림-설정.json')
    expect(await text(folder, SETTINGS_FILE)).toBe('{ 망가진')
    expect(await folder.read(RECORDS_FILE)).toBeNull()

    const newer = new MemoryFolder()
    await newer.write(RECORDS_FILE, '{"app":"ullim","kind":"records","version":9}')
    const newerResult = await openRecordFolder(newer, mine, new Set(), undefined, now)
    expect(!newerResult.ok && newerResult.message).toContain('더 새 판')
    expect(await newer.read(SETTINGS_FILE)).toBeNull()
  })

  it('다른 곳으로 옮겨 쓰기: 설정·기록·녹음만 (다른 파일은 옮기지 않는다)', async () => {
    const from = new MemoryFolder()
    await from.write(SETTINGS_FILE, 'S')
    await from.write('녹음/Ullim-1.wav', new Blob([new Uint8Array([1, 2])]))
    await from.write('메모.txt', 'x')
    const to = new MemoryFolder()
    await to.write('녹음/Ullim-0.wav', new Blob([new Uint8Array([9])]))
    await copyRecordFolder(from, to)
    expect(to.paths.sort()).toEqual([SETTINGS_FILE, '녹음/Ullim-0.wav', '녹음/Ullim-1.wav'].sort())
  })
})

describe('기록 파일 (zip)', () => {
  it('파일 이름: 울림-기록-날짜-시각.zip', () => {
    expect(recordFileName(new Date(2026, 9, 25, 20, 12))).toBe('울림-기록-20261025-2012.zip')
  })

  it('녹음 폴더에는 숨김 파일이 아닌 .wav만', () => {
    expect(isRecordingName('Ullim-20261025-2012.wav')).toBe(true)
    expect(isRecordingName('._Ullim.wav')).toBe(false)
    expect(isRecordingName('memo.txt')).toBe(false)
  })

  it('묶었다 풀면 설정·기록·녹음이 그대로이고, 기록 폴더 밖의 파일은 담지 않는다', async () => {
    const folder = new MemoryFolder()
    await folder.write(SETTINGS_FILE, encodeSettingsFile(mine, now))
    await folder.write(RECORDS_FILE, encodeRecordsFile(EMPTY_RECORDS, now))
    await folder.write('녹음/Ullim-20261025-2012.wav', new Blob([new Uint8Array([82, 73, 70, 70])]))
    await folder.write('녹음/메모.txt', 'x')
    const result = await unpackRecordFile(await packRecordFolder(folder, now))
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.recordingCount).toBe(1)
    expect(result.folder.paths.sort()).toEqual([SETTINGS_FILE, RECORDS_FILE, '녹음/Ullim-20261025-2012.wav'].sort())
    expect(parseSettingsFile((await text(result.folder, SETTINGS_FILE))!)).toEqual({ ok: true, value: mine })
    const wav = await result.folder.read('녹음/Ullim-20261025-2012.wav')
    expect([...new Uint8Array(await wav!.arrayBuffer())]).toEqual([82, 73, 70, 70])
  })

  it('폴더째 압축한 파일, 맥에서 만든 한글 이름(자모 분리), 맥이 붙인 __MACOSX도 읽는다', async () => {
    const encoder = new TextEncoder()
    const zip = zipSync({
      [`울림 기록/${SETTINGS_FILE}`.normalize('NFD')]: encoder.encode(encodeSettingsFile(mine, now)),
      [`울림 기록/녹음/Ullim-1.wav`.normalize('NFD')]: new Uint8Array([1]),
      '__MACOSX/울림 기록/._울림-설정.json': new Uint8Array([0]),
      '울림 기록/../밖.wav': new Uint8Array([2]),
    })
    const result = await unpackRecordFile(zip)
    expect(result.ok && result.folder.paths.sort()).toEqual([SETTINGS_FILE, '녹음/Ullim-1.wav'].sort())
  })

  it.each([
    ['zip이 아닌 파일', new TextEncoder().encode('그냥 글자'), 'zip 파일인지'],
    ['울림 파일이 없는 zip', zipSync({ 'a.txt': new Uint8Array([1]) }), '울림 기록 파일이 아니에요'],
    ['망가진 설정 파일', zipSync({ [SETTINGS_FILE]: new TextEncoder().encode('{') }), '울림-설정.json'],
  ])('불러오지 못하는 경우: %s', async (_, bytes, message) => {
    const result = await unpackRecordFile(bytes)
    expect(result.ok).toBe(false)
    expect(!result.ok && result.message).toContain(message)
  })
})
