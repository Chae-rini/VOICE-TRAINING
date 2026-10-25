import { unzipSync, zipSync, type Zippable } from 'fflate'
import { parseFailureMessage, parseRecordsFile, parseSettingsFile, RECORDINGS_DIRECTORY, RECORDS_FILE, SETTINGS_FILE } from './archive'
import { MemoryFolder, type RecordFolder } from './recordFolder'

/**
 * 기록 파일(zip): 기록 폴더와 같은 모양(`울림-설정.json`, `울림-기록.json`, `녹음/*.wav`)을 파일 하나로 묶는다.
 * 폴더를 고를 수 없는 브라우저(아이폰·맥 사파리, Firefox)는 이 파일로 저장하고 다음에 불러온다. 다른 기기로 옮길 때도 쓴다.
 * 압축 풀기는 fflate(MIT)로 한다.
 */

/** [byte] 불러올 수 있는 기록 파일의 풀린 크기 (휴대폰 메모리를 넘지 않게) */
export const MAX_RECORD_FILE_BYTES = 512 * 1024 * 1024

/** 예: 울림-기록-20261025-2012.zip (새로 저장할수록 이름이 뒤로 가게 날짜·시각을 붙인다) */
export function recordFileName(date: Date): string {
  const two = (value: number) => String(value).padStart(2, '0')
  const day = `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}`
  return `울림-기록-${day}-${two(date.getHours())}${two(date.getMinutes())}.zip`
}

/** 녹음 폴더에 들어갈 수 있는 파일 이름: 숨김 파일이 아닌 .wav 하나 */
export function isRecordingName(name: string): boolean {
  return /^[^./\\][^/\\]*\.wav$/i.test(name)
}

export async function packRecordFolder(folder: RecordFolder, now = new Date()): Promise<Uint8Array> {
  const entries: Zippable = {}
  const add = async (path: string, level: 0 | 6) => {
    const blob = await folder.read(path)
    if (blob !== null) entries[path] = [new Uint8Array(await blob.arrayBuffer()), { level, mtime: now }]
  }
  await add(SETTINGS_FILE, 6)
  await add(RECORDS_FILE, 6)
  for (const name of (await folder.list(RECORDINGS_DIRECTORY)).filter(isRecordingName).sort()) {
    // WAV는 거의 줄지 않으니 압축하지 않고 담는다 (휴대폰에서 빨리 저장되게)
    await add(`${RECORDINGS_DIRECTORY}/${name}`, 0)
  }
  return zipSync(entries)
}

export type UnpackResult =
  | { readonly ok: true; readonly folder: MemoryFolder; readonly recordingCount: number }
  | { readonly ok: false; readonly message: string }

/**
 * 기록 파일을 풀어 메모리 폴더로. 울림 파일만 꺼내고 나머지(맥이 붙이는 __MACOSX 등)는 버린다.
 * 폴더째 압축한 파일(`울림 기록/울림-설정.json`처럼 맨 위 폴더가 하나 더 있는 것)도 읽는다. 맥에서 만든 한글 이름(자모 분리)도 맞춰 읽는다.
 */
export async function unpackRecordFile(bytes: Uint8Array): Promise<UnpackResult> {
  const notRecordFile = { ok: false, message: '울림 기록 파일이 아니에요. ‘울림-기록-날짜.zip’ 파일을 골라 주세요.' } as const
  // 1) 이름과 크기만 훑는다 (풀지 않음)
  const names = new Map<string, { raw: string; size: number }>()
  try {
    unzipSync(bytes, {
      filter: (file) => {
        names.set(file.name.normalize('NFC'), { raw: file.name, size: file.originalSize })
        return false
      },
    })
  } catch {
    return { ok: false, message: '기록 파일을 읽지 못했어요. zip 파일인지 확인해 주세요.' }
  }
  const prefix = [SETTINGS_FILE, RECORDS_FILE].some((file) => names.has(file))
    ? ''
    : [...names.keys()].map((name) => name.match(/^([^/]+\/)(울림-설정\.json|울림-기록\.json)$/)?.[1]).find((p) => p !== undefined)
  if (prefix === undefined) return notRecordFile

  // 2) 꺼낼 파일을 정하고 크기를 확인한다
  const wanted = new Map<string, string>() // 압축 안의 원래 이름 → 기록 폴더 경로
  let total = 0
  for (const [name, { raw, size }] of names) {
    if (!name.startsWith(prefix)) continue
    const path = name.slice(prefix.length)
    const [directory, file, ...rest] = path.split('/')
    const isWanted =
      path === SETTINGS_FILE || path === RECORDS_FILE || (directory === RECORDINGS_DIRECTORY && file !== undefined && rest.length === 0 && isRecordingName(file))
    if (!isWanted) continue
    wanted.set(raw, path)
    total += size
  }
  if (total > MAX_RECORD_FILE_BYTES) return { ok: false, message: '기록 파일이 너무 커요 (풀면 512 MB가 넘어요). 녹음 일부를 지운 기록 파일로 다시 저장해 주세요.' }

  // 3) 꺼내서 두 JSON을 확인한다 (읽지 못하면 불러오지 않는다)
  let files: Record<string, Uint8Array>
  try {
    files = unzipSync(bytes, { filter: (file) => wanted.has(file.name) })
  } catch {
    return { ok: false, message: '기록 파일을 읽지 못했어요. 파일이 망가졌을 수 있어요.' }
  }
  const folder = new MemoryFolder()
  let recordingCount = 0
  for (const [raw, data] of Object.entries(files)) {
    const path = wanted.get(raw)!
    if (path === SETTINGS_FILE || path === RECORDS_FILE) {
      const text = new TextDecoder().decode(data)
      const parsed = path === SETTINGS_FILE ? parseSettingsFile(text) : parseRecordsFile(text)
      if (!parsed.ok) return { ok: false, message: parseFailureMessage(path, parsed.reason) }
      await folder.write(path, text)
    } else {
      await folder.write(path, new Blob([data as Uint8Array<ArrayBuffer>], { type: 'audio/wav' }))
      recordingCount += 1
    }
  }
  return { ok: true, folder, recordingCount }
}
