import {
  mergeVoiceSettings,
  sameVoiceSettings,
  type VoiceSettingField,
  type VoiceSettings,
} from '../model/voiceSettings'
import {
  EMPTY_RECORDS,
  encodeRecordsFile,
  mergeRecords,
  recordCount,
  encodeSettingsFile,
  parseFailureMessage,
  parseRecordsFile,
  parseSettingsFile,
  RECORDINGS_DIRECTORY,
  RECORDS_FILE,
  SETTINGS_FILE,
  type RecordsData,
} from './archive'
import type { RecordFolder } from './recordFolder'

export type OpenResult =
  | { readonly ok: true; readonly settings: VoiceSettings; readonly records: RecordsData }
  | { readonly ok: false; readonly message: string }

/**
 * 기록 폴더를 연다: 두 파일을 읽고, 화면의 값과 합쳐(`mergeVoiceSettings`) 달라졌으면 설정 파일을 고쳐 쓴다.
 * 화면에 쌓인 기록(`currentRecords`, 폴더를 고르기 전·다시 연결하기 전의 것) 중 폴더에 없는 것은 기록 파일에 더한다.
 * 빈 폴더면 화면의 값(예전에 이 브라우저에 있던 값 포함)으로 두 파일을 새로 만든다.
 * 읽지 못한 파일이 하나라도 있으면 아무것도 쓰지 않고 까닭을 돌려준다.
 */
export async function openRecordFolder(
  folder: RecordFolder,
  current: VoiceSettings,
  changed: ReadonlySet<VoiceSettingField>,
  currentRecords: RecordsData = EMPTY_RECORDS,
  now = new Date(),
): Promise<OpenResult> {
  const settingsBlob = await folder.read(SETTINGS_FILE)
  const recordsBlob = await folder.read(RECORDS_FILE)
  const folderSettings = settingsBlob === null ? null : parseSettingsFile(await settingsBlob.text())
  if (folderSettings !== null && !folderSettings.ok) return { ok: false, message: parseFailureMessage(SETTINGS_FILE, folderSettings.reason) }
  const records = recordsBlob === null ? null : parseRecordsFile(await recordsBlob.text())
  if (records !== null && !records.ok) return { ok: false, message: parseFailureMessage(RECORDS_FILE, records.reason) }

  const settings = folderSettings === null ? current : mergeVoiceSettings(folderSettings.value, current, changed)
  if (folderSettings === null || !sameVoiceSettings(settings, folderSettings.value)) {
    await folder.write(SETTINGS_FILE, encodeSettingsFile(settings, now))
  }
  const folderRecords = records?.value ?? EMPTY_RECORDS
  const mergedRecords = mergeRecords(folderRecords, currentRecords)
  if (records === null || recordCount(mergedRecords) > recordCount(folderRecords)) {
    await folder.write(RECORDS_FILE, encodeRecordsFile(mergedRecords, now))
  }
  return { ok: true, settings, records: mergedRecords }
}

/** 한 기록 폴더의 울림 파일(설정·기록·녹음)을 다른 곳으로 옮겨 쓴다 (기록 파일을 고른 폴더에 불러올 때) */
export async function copyRecordFolder(from: RecordFolder, to: RecordFolder): Promise<void> {
  for (const path of [SETTINGS_FILE, RECORDS_FILE]) {
    const blob = await from.read(path)
    if (blob !== null) await to.write(path, blob)
  }
  await copyRecordings(from, to)
}

/** 녹음 폴더의 소리 파일만 옮겨 쓴다 (폴더를 고르기 전에 화면에 담아 둔 녹음을 폴더에 넣을 때) */
export async function copyRecordings(from: RecordFolder, to: RecordFolder): Promise<void> {
  for (const name of await from.list(RECORDINGS_DIRECTORY)) {
    const blob = await from.read(`${RECORDINGS_DIRECTORY}/${name}`)
    if (blob !== null) await to.write(`${RECORDINGS_DIRECTORY}/${name}`, blob)
  }
}
