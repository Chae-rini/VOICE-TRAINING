import type { RecordItems } from '../model/records'
import { settings } from '../model/settings.svelte'
import { EMPTY_VOICE_SETTINGS, type VoiceSettingField, type VoiceSettings } from '../model/voiceSettings'
import { isNativeApp } from '../platform/app'
import { saveFile } from '../practice/sharing'
import {
  EMPTY_RECORDS,
  encodeRecordsFile,
  encodeSettingsFile,
  mergeRecords,
  parseRecordsFile,
  recordIdOf,
  parseSettingsFile,
  RECORDINGS_DIRECTORY,
  recordingFileName,
  RECORDS_FILE,
  SETTINGS_FILE,
  withRecord,
  type RecordList,
  type RecordsData,
} from './archive'
import { loadFolderHandle, saveFolderHandle } from './handleStore'
import { ensureNativeStoragePermission, NativeFolder } from './nativeFolder'
import { copyRecordFolder, copyRecordings, openRecordFolder } from './openFolder'
import { DirectoryFolder, MemoryFolder, type RecordFolder } from './recordFolder'
import { packRecordFolder, recordFileName, unpackRecordFile } from './recordZip'

/** 기록 하나를 남긴 결과: 기록 폴더에 씀 / 화면에만 담음(폴더를 아직 안 골랐거나 기록 파일로 저장 전, 또는 쓰지 못해 다음에 다시 씀) / 녹음 소리를 쓰지 못해 남기지 않음 */
export type AddResult = 'saved' | 'pending' | 'failed'

/**
 * 내 기록이 어디에 남는지: 브라우저가 아니라 내가 고른 폴더, 또는 내가 저장하는 기록 파일 (W6, 사용자 결정).
 * 안드로이드 앱은 폴더를 고르지 않고 휴대폰의 ‘문서/울림’에 바로 쓴다 (A2, 사용자 결정).
 * - none: 폴더를 고를 수 있는 브라우저인데 아직 고르지 않음 (바꾼 값은 페이지를 닫으면 사라진다). 앱은 ‘문서/울림’을 열기 전이나 열지 못했을 때
 * - needsPermission: 전에 고른 폴더가 있지만 브라우저가 다시 허락을 받으라고 함 (버튼을 눌러야 물을 수 있다)
 * - connected: 고른 폴더에 바로 쓰는 중
 * - memory: 폴더를 고를 수 없는 브라우저(사파리·Firefox). 기록 파일(zip)로 저장하고 다음에 불러온다
 */
export type StorageStatus =
  | { readonly kind: 'none' }
  | { readonly kind: 'needsPermission'; readonly folderName: string }
  | { readonly kind: 'connected'; readonly folderName: string }
  | { readonly kind: 'memory' }

/** [ms] 슬라이더를 끄는 동안 파일을 여러 번 쓰지 않게 잠깐 모았다가 쓴다 */
const SAVE_DELAY = 400

function writeErrorMessage(error: unknown): string {
  if (error instanceof DOMException && error.name === 'QuotaExceededError') return '저장 공간이 부족해 기록 폴더에 쓰지 못했어요.'
  return '기록 폴더에 저장하지 못했어요. 폴더가 옮겨졌거나 지워졌는지 확인해 주세요.'
}

function isPermissionError(error: unknown): boolean {
  return error instanceof DOMException && (error.name === 'NotAllowedError' || error.name === 'SecurityError')
}

class RecordStore {
  /** 안드로이드 앱 안인지. 앱은 폴더를 고르지 않고 ‘문서/울림’에 바로 쓴다 */
  readonly isApp: boolean
  /** 이 브라우저가 폴더를 고를 수 있는지 (개발 서버에서 주소 끝에 `?nofolder`를 붙이면 사파리처럼 동작한다) */
  readonly canPickFolder: boolean
  status: StorageStatus = $state({ kind: 'none' })
  /** 폴더를 열거나 기록 파일을 만드는 중 */
  busy = $state(false)
  /** 아직 기록 폴더에 쓰지 않았거나 기록 파일로 저장하지 않은 바뀐 내용이 있는지 */
  unsaved = $state(false)
  errorMessage: string | null = $state(null)
  infoMessage: string | null = $state(null)
  /** 마지막으로 폴더에 쓰거나 기록 파일로 저장한 때 */
  savedAt: Date | null = $state(null)
  /** 이번에 기록 파일을 불러오거나 저장했는지 (폴더를 고를 수 없는 브라우저에서 불러오기 안내를 그만 보이게) */
  usedRecordFile = $state(false)
  /** 연습 기록·남긴 녹음·재기 이력 (항목 모양은 `model/records.ts`) */
  records: RecordsData = $state.raw(EMPTY_RECORDS)

  #handle: FileSystemDirectoryHandle | null = null
  /** 연결된 기록 폴더 (connected일 때만) */
  #folder: RecordFolder | null = null
  /** 기록 폴더가 없을 때 남긴 녹음 소리를 들고 있는 곳 (폴더를 고르면 옮기고, 기록 파일로 저장할 때 함께 묶는다) */
  #memory = new MemoryFolder()
  /** 기록 폴더에 아직 쓰지 않은 기록이 있는지 */
  #recordsDirty = false
  /** 이번에 화면에서 바꾸고 아직 폴더에 쓰지 않은 값 */
  #changed = new Set<VoiceSettingField>()
  #saveTimer: ReturnType<typeof setTimeout> | null = null
  /** 파일 쓰기를 한 줄로 세운다 (같은 파일을 동시에 쓰지 않게) */
  #writing: Promise<void> = Promise.resolve()
  #started = false

  constructor() {
    const forceMemory = import.meta.env.DEV && new URLSearchParams(globalThis.location?.search).has('nofolder')
    this.isApp = isNativeApp()
    // 앱의 웹뷰에도 폴더 고르기 함수는 있지만, 부르면 창 없이 바로 취소된다 (A1 확인)
    this.canPickFolder =
      !this.isApp &&
      !forceMemory &&
      typeof globalThis.window?.showDirectoryPicker === 'function' &&
      globalThis.isSecureContext === true
    this.status = this.canPickFolder || this.isApp ? { kind: 'none' } : { kind: 'memory' }
  }

  /** 앱을 열 때 한 번: 전에 고른 폴더가 있으면 다시 연결한다 (허락이 남아 있을 때만 바로) */
  async start(): Promise<void> {
    if (this.#started) return
    this.#started = true
    settings.observeVoiceChanges((field) => this.#voiceChanged(field))
    // 예전(W3~W5)에 이 브라우저에 있던 값은 아직 파일로 옮겨지지 않았다
    this.unsaved = settings.hasLegacyValues
    addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') void this.#flush()
    })
    addEventListener('beforeunload', (event) => {
      // 폴더에 쓰지 못한 바뀐 내용이 있으면 브라우저가 떠나기 전에 한 번 묻게 한다
      if (this.unsaved) event.preventDefault()
    })
    if (this.isApp) {
      await this.connectAppFolder()
      return
    }
    if (!this.canPickFolder) return
    const handle = await loadFolderHandle()
    if (handle === null) return
    this.#handle = handle
    const permission = (await handle.queryPermission?.({ mode: 'readwrite' })) ?? 'granted'
    if (permission === 'granted') await this.#connect(handle)
    else this.status = { kind: 'needsPermission', folderName: handle.name }
  }

  // MARK: - 기록 폴더

  /** 앱: 휴대폰의 ‘문서/울림’을 기록 폴더로 연다 (앱을 켤 때, 열지 못했으면 ‘다시 열기’ 버튼으로) */
  async connectAppFolder(): Promise<void> {
    if (!this.isApp || this.busy) return
    this.#clearMessages()
    if (!(await ensureNativeStoragePermission())) {
      this.errorMessage = '휴대폰의 문서 폴더에 저장할 수 있게 허락해야 기록이 남아요.'
      return
    }
    await this.#flush()
    await this.#connectFolder(new NativeFolder(), null)
  }

  /** 폴더 고르기 창을 띄워 기록 폴더를 정한다 (버튼을 누른 그때 불러야 한다) */
  async chooseFolder(): Promise<void> {
    const picker = globalThis.window?.showDirectoryPicker
    if (picker === undefined || this.busy || this.isApp) return
    this.#clearMessages()
    let handle: FileSystemDirectoryHandle
    try {
      handle = await picker.call(window, { id: 'ullim-records', mode: 'readwrite', startIn: 'documents' })
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'AbortError')) this.errorMessage = '폴더를 고르지 못했어요. 다시 시도해 주세요.'
      return
    }
    await this.connectHandle(handle)
  }

  /** 전에 고른 폴더에 다시 연결한다. 브라우저가 허락을 묻는다 (버튼을 누른 그때 불러야 한다) */
  async reconnect(): Promise<void> {
    const handle = this.#handle
    if (handle === null || this.busy) return
    this.#clearMessages()
    const permission = (await handle.requestPermission?.({ mode: 'readwrite' }).catch(() => 'denied' as const)) ?? 'granted'
    if (permission !== 'granted') {
      this.errorMessage = '폴더를 쓸 수 있게 허락해야 기록이 남아요.'
      return
    }
    await this.#connect(handle)
  }

  /** 이 폴더를 기록 폴더로 쓰고 다음에도 기억한다 */
  async connectHandle(handle: FileSystemDirectoryHandle): Promise<void> {
    await this.#flush()
    if (await this.#connect(handle)) await saveFolderHandle(handle)
  }

  /** 이 브라우저에서 폴더 연결을 끊는다 (폴더의 파일은 그대로 둔다) */
  async disconnect(): Promise<void> {
    await this.#flush()
    this.#folder = null
    this.#handle = null
    await saveFolderHandle(null)
    // 기록은 폴더에 있다. 끊은 뒤 화면에서 고친 기록이 다시 연결할 때 폴더 기록과 엇갈리지 않게 화면의 기록도 비운다.
    this.records = EMPTY_RECORDS
    this.#recordsDirty = false
    this.status = { kind: 'none' }
    this.#clearMessages()
    this.infoMessage = '연결을 끊었어요. 폴더의 파일은 그대로 있어요.'
  }

  async #connect(handle: FileSystemDirectoryHandle): Promise<boolean> {
    return this.#connectFolder(new DirectoryFolder(handle), handle)
  }

  /** 기록 폴더를 열어 화면의 값·기록과 합친다. 고른 폴더면 그 핸들도 기억한다 (앱의 ‘문서/울림’은 핸들이 없다) */
  async #connectFolder(folder: RecordFolder, handle: FileSystemDirectoryHandle | null): Promise<boolean> {
    this.busy = true
    this.errorMessage = null
    try {
      const result = await openRecordFolder(folder, settings.voiceSettings, this.#changed, this.records)
      if (!result.ok) {
        this.errorMessage = result.message
        return false
      }
      // 폴더를 고르기 전에 담아 둔 녹음 소리도 폴더로 옮긴다 (기록은 위에서 합쳤다)
      await copyRecordings(this.#memory, folder)
      this.#memory = new MemoryFolder()
      this.#handle = handle
      this.#folder = folder
      this.records = result.records
      this.#recordsDirty = false
      settings.applyVoiceSettings(result.settings)
      settings.forgetLegacyValues()
      this.#changed.clear()
      this.unsaved = false
      this.savedAt = new Date()
      this.status = { kind: 'connected', folderName: folder.name }
      return true
    } catch (error) {
      this.errorMessage = isPermissionError(error) ? '폴더를 쓸 수 있게 허락해야 기록이 남아요.' : writeErrorMessage(error)
      return false
    } finally {
      this.busy = false
    }
  }

  #voiceChanged(field: VoiceSettingField): void {
    this.#changed.add(field)
    if (this.#folder === null) {
      this.unsaved = true
      return
    }
    if (this.#saveTimer !== null) clearTimeout(this.#saveTimer)
    this.#saveTimer = setTimeout(() => void this.#flush(), SAVE_DELAY)
  }

  /**
   * 기록 하나를 더한다. 녹음 소리(`wav`)가 있으면 먼저 녹음 폴더에 쓰고, 쓰지 못하면 기록도 남기지 않는다 (반쪽 기록이 없게).
   * 기록 폴더가 있으면 바로 쓰고, 없으면 화면에 담아 두었다가 폴더를 고르거나 기록 파일로 저장할 때 함께 남긴다.
   */
  async addRecord<K extends RecordList>(list: K, item: RecordItems[K], wav?: { name: string; blob: Blob }): Promise<AddResult> {
    if (wav !== undefined) {
      try {
        await (this.#folder ?? this.#memory).write(`${RECORDINGS_DIRECTORY}/${wav.name}`, wav.blob)
      } catch (error) {
        this.errorMessage = writeErrorMessage(error)
        return 'failed'
      }
    }
    this.records = withRecord(this.records, list, item)
    this.#recordsDirty = true
    if (this.#folder === null) {
      this.unsaved = true
      return 'pending'
    }
    await this.#flush()
    return this.#recordsDirty ? 'pending' : 'saved'
  }

  /** 기록 하나의 일부(메모·언어 등)를 고친다 */
  async updateRecord<K extends RecordList>(list: K, id: string, patch: Partial<RecordItems[K]>): Promise<AddResult> {
    if (!this.#canEditRecords()) return 'failed'
    const items = this.records[list].map((item) => (recordIdOf(item) === id ? { ...(item as object), ...patch } : item))
    return this.#replaceRecords({ ...this.records, [list]: items })
  }

  /** 기록 하나를 지운다. 남긴 녹음이면 기록을 지운 뒤 소리 파일도 지운다 (기록만 남고 소리가 없는 일은 없게) */
  async removeRecord(list: RecordList, id: string): Promise<AddResult> {
    if (!this.#canEditRecords()) return 'failed'
    const removed = this.records[list].filter((item) => recordIdOf(item) === id)
    const result = await this.#replaceRecords({ ...this.records, [list]: this.records[list].filter((item) => recordIdOf(item) !== id) })
    if (list === 'recordings') await this.#removeSounds(removed, result)
    return result
  }

  /** 연습 기록·남긴 녹음(소리 포함)·재기 이력을 모두 지운다. 지금 쓰는 기준·목표 범위·모음 지도(설정 파일)는 그대로 */
  async removeAllRecords(): Promise<AddResult> {
    if (!this.#canEditRecords()) return 'failed'
    const recordings = this.records.recordings
    const result = await this.#replaceRecords(EMPTY_RECORDS)
    await this.#removeSounds(recordings, result)
    return result
  }

  /** 남긴 녹음의 소리. 파일이 없으면 null */
  async readRecording(fileName: string): Promise<Blob | null> {
    try {
      return await (this.#folder ?? this.#memory).read(`${RECORDINGS_DIRECTORY}/${fileName}`)
    } catch {
      return null
    }
  }

  /** 다시 연결해야 하는 동안은 고치거나 지우지 않는다 (다시 연결할 때 폴더의 기록과 엇갈리지 않게) */
  #canEditRecords(): boolean {
    if (this.status.kind !== 'needsPermission') return true
    this.errorMessage = '기록 폴더에 다시 연결한 뒤에 고치거나 지울 수 있어요.'
    return false
  }

  async #replaceRecords(next: RecordsData): Promise<AddResult> {
    this.records = next
    this.#recordsDirty = true
    if (this.#folder === null) {
      this.unsaved = true
      return 'pending'
    }
    await this.#flush()
    return this.#recordsDirty ? 'pending' : 'saved'
  }

  /** 지운 기록의 소리 파일을 지운다. 폴더에 쓰지 못했으면(기록이 아직 폴더에 남았으면) 소리도 남겨 둔다 */
  async #removeSounds(removed: readonly unknown[], result: AddResult): Promise<void> {
    if (result === 'failed' || (result === 'pending' && this.#folder !== null)) return
    for (const item of removed) {
      const fileName = (item as { fileName?: unknown } | null)?.fileName
      if (typeof fileName !== 'string') continue
      try {
        await (this.#folder ?? this.#memory).remove(`${RECORDINGS_DIRECTORY}/${fileName}`)
      } catch {
        // 소리 파일을 못 지워도 기록은 지워졌다. 폴더에 남은 파일은 사용자가 지울 수 있다.
      }
    }
  }

  /** 개발용 가짜 기록을 넣는다 (기록 폴더에 연결돼 있지 않을 때만, 화면에만) */
  seedRecords(samples: RecordsData): boolean {
    if (this.#folder !== null) return false
    this.records = mergeRecords(this.records, samples)
    this.#recordsDirty = true
    this.unsaved = true
    return true
  }

  /** 남긴 녹음에 붙일 새 파일 이름 (녹음 폴더에 같은 이름이 있으면 -2, -3) */
  async newRecordingFileName(date: Date): Promise<string> {
    return recordingFileName(date, new Set(await (this.#folder ?? this.#memory).list(RECORDINGS_DIRECTORY)))
  }

  /** 이 id의 남긴 녹음이 기록에 있는지 */
  hasRecording(id: string): boolean {
    return this.records.recordings.some((item) => recordIdOf(item) === id)
  }

  /** 모아 둔 바뀐 값과 기록을 기록 폴더에 쓴다 */
  #flush(): Promise<void> {
    if (this.#saveTimer !== null) clearTimeout(this.#saveTimer)
    this.#saveTimer = null
    this.#writing = this.#writing.then(async () => {
      const folder = this.#folder
      if (folder === null || (this.#changed.size === 0 && !this.#recordsDirty)) return
      const fields = [...this.#changed]
      const recordsDirty = this.#recordsDirty
      this.#changed.clear()
      this.#recordsDirty = false
      try {
        const now = new Date()
        if (fields.length > 0) await folder.write(SETTINGS_FILE, encodeSettingsFile(settings.voiceSettings, now))
        if (recordsDirty) await folder.write(RECORDS_FILE, encodeRecordsFile(this.records, now))
        this.unsaved = this.#changed.size > 0 || this.#recordsDirty
        this.savedAt = now
        this.errorMessage = null
      } catch (error) {
        fields.forEach((field) => this.#changed.add(field))
        if (recordsDirty) this.#recordsDirty = true
        this.unsaved = true
        if (isPermissionError(error)) {
          // 브라우저가 허락을 거두었다: 다시 연결하면 바뀐 값을 폴더에 쓴다
          this.#folder = null
          this.status = { kind: 'needsPermission', folderName: folder.name }
          this.errorMessage = '기록 폴더에 쓸 허락이 없어졌어요. 다시 연결해 주세요.'
        } else {
          this.errorMessage = writeErrorMessage(error)
        }
      }
    })
    return this.#writing
  }

  // MARK: - 기록 파일 (zip)

  /** 기록 파일(zip)을 만들어 이 기기에 내려받는다. 폴더에 연결돼 있으면 폴더의 내용을, 아니면 지금 화면의 내용을 담는다 */
  async exportFile(): Promise<void> {
    if (this.busy) return
    this.busy = true
    this.#clearMessages()
    try {
      await this.#flush()
      const source = this.#folder ?? (await this.#memorySnapshot())
      const now = new Date()
      const file = new File([(await packRecordFolder(source, now)) as Uint8Array<ArrayBuffer>], recordFileName(now), {
        type: 'application/zip',
      })
      // 앱은 내려받기가 안 되어서 ‘문서/울림/내보낸 파일’에 저장한다 (그 위치를 돌려받는다)
      const savedPath = await saveFile(file)
      this.usedRecordFile = true
      if (this.#folder === null) {
        this.#changed.clear()
        this.#recordsDirty = false
        this.unsaved = false
        this.savedAt = now
        settings.forgetLegacyValues()
      }
      // 파일 이름이 늘 .zip(‘집’)으로 끝나서 조사는 ‘으로’
      this.infoMessage =
        savedPath !== null
          ? `‘${savedPath}’에 저장했어요. 다른 기기나 다시 설치한 앱에서 ‘기록 파일 불러오기’로 열 수 있어요.`
          : this.#folder === null
            ? `‘${file.name}’으로 저장했어요. 다음에 열 때 이 파일을 불러오면 돼요.`
            : `‘${file.name}’으로 저장했어요. 다른 기기에서 ‘기록 파일 불러오기’로 열 수 있어요.`
    } catch {
      this.errorMessage = '기록 파일을 만들지 못했어요. 저장 공간을 확인해 주세요.'
    } finally {
      this.busy = false
    }
  }

  /**
   * 기록 파일(zip)을 불러온다. 지금 화면의 내 기준 값과 기록은 파일의 것으로 바뀐다.
   * 기록 폴더에 연결돼 있으면 파일의 내용을 폴더에 쓴다(설정·기록 파일은 바뀌고, 다른 녹음은 그대로 둔다).
   */
  async importFile(file: File): Promise<void> {
    if (this.busy) return
    this.busy = true
    this.#clearMessages()
    try {
      await this.#flush()
      const result = await unpackRecordFile(new Uint8Array(await file.arrayBuffer()))
      if (!result.ok) {
        this.errorMessage = result.message
        return
      }
      const voice = await readSettings(result.folder)
      const records = await readRecords(result.folder)
      const target = this.#folder ?? new MemoryFolder()
      await copyRecordFolder(result.folder, target)
      const now = new Date()
      await target.write(SETTINGS_FILE, encodeSettingsFile(voice, now))
      await target.write(RECORDS_FILE, encodeRecordsFile(records, now))
      if (this.#folder === null) this.#memory = target as MemoryFolder
      this.records = records
      this.#recordsDirty = false
      this.usedRecordFile = true
      settings.applyVoiceSettings(voice)
      settings.forgetLegacyValues()
      this.#changed.clear()
      this.unsaved = false
      this.savedAt = this.#folder === null ? null : now
      const count = result.recordingCount
      this.infoMessage = `‘${file.name}’에서 불러왔어요${count > 0 ? ` (녹음 ${count}개)` : ''}.`
    } catch (error) {
      this.errorMessage = this.#folder !== null ? writeErrorMessage(error) : '기록 파일을 불러오지 못했어요.'
    } finally {
      this.busy = false
    }
  }

  /** 메모리 폴더에 지금 값을 써 넣고 돌려준다 (기록 파일로 묶기 전에) */
  async #memorySnapshot(): Promise<RecordFolder> {
    const now = new Date()
    await this.#memory.write(SETTINGS_FILE, encodeSettingsFile(settings.voiceSettings, now))
    await this.#memory.write(RECORDS_FILE, encodeRecordsFile(this.records, now))
    return this.#memory
  }

  #clearMessages(): void {
    this.errorMessage = null
    this.infoMessage = null
  }
}

/** 풀어 둔 기록 파일의 설정 (없으면 빈 값. 이미 확인한 파일이라 읽지 못할 일은 없다) */
async function readSettings(folder: RecordFolder): Promise<VoiceSettings> {
  const blob = await folder.read(SETTINGS_FILE)
  const parsed = blob === null ? null : parseSettingsFile(await blob.text())
  return parsed?.ok ? parsed.value : EMPTY_VOICE_SETTINGS
}

async function readRecords(folder: RecordFolder): Promise<RecordsData> {
  const blob = await folder.read(RECORDS_FILE)
  const parsed = blob === null ? null : parseRecordsFile(await blob.text())
  return parsed?.ok ? parsed.value : EMPTY_RECORDS
}

export const store = new RecordStore()
