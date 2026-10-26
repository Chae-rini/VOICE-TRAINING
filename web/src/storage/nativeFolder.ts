import { Directory, Filesystem, type FilesystemPlugin } from '@capacitor/filesystem'
import { splitPath, type RecordFolder } from './recordFolder'

/** 쓰는 파일 시스템 기능만 (시험할 때 가짜를 끼운다) */
export type NativeFilesystem = Pick<
  FilesystemPlugin,
  'readFile' | 'writeFile' | 'appendFile' | 'deleteFile' | 'readdir' | 'stat'
>

/**
 * [byte] 한 번에 앱으로 넘기는 크기. 안드로이드에는 파일 내용을 base64 글자로만 넘길 수 있어서(Blob은 웹에서만),
 * 3분 녹음(약 17 MB)을 한 번에 넘기지 않고 나눠 이어 쓴다. 3의 배수라 조각마다 base64 끝에 채움 글자(=)가 붙지 않는다.
 */
export const NATIVE_CHUNK_BYTES = 768 * 1024

/** 휴대폰의 기록 폴더: 공용 ‘문서’ 폴더 안의 ‘울림’ (파일 앱에서 보이고, 앱을 지워도 남는다) */
export const APP_RECORD_ROOT = '울림'
/** ‘울림’을 쓰지 못할 때 차례로 써 볼 폴더 수 (‘울림-2’ … ‘울림-9’) */
const MAX_APP_RECORD_ROOTS = 9

/** 화면에 보일 이름. 예: ‘울림-2’ → ‘문서/울림-2’ */
export function appRecordFolderName(root: string): string {
  return `문서/${root}`
}

/**
 * 앱을 지웠다 다시 깔면, 새 앱은 예전 앱이 만든 파일을 열지도 같은 이름으로 쓰지도 못한다 (안드로이드 11 이상, A3 확인).
 * 그래서 ‘울림’을 쓰지 못하면 ‘울림-2’, ‘울림-3’…에 새로 쓴다. 마지막으로 쓴 폴더(`remembered`)를 먼저 열어 본다.
 */
export function appRecordRoots(remembered: string | null): string[] {
  const roots = [APP_RECORD_ROOT]
  for (let n = 2; n <= MAX_APP_RECORD_ROOTS; n++) roots.push(`${APP_RECORD_ROOT}-${n}`)
  return remembered !== null && roots.includes(remembered) ? [remembered, ...roots.filter((root) => root !== remembered)] : roots
}

/** 폴더 하나를 열어 본 결과: 연결함 / 파일 내용을 읽지 못함(망가짐·더 새 판, 덮어쓰지 않고 멈춘다) / 쓰지 못함(다음 폴더로) */
export type AppFolderAttempt = 'connected' | 'unreadable' | 'writeFailed'

/**
 * 후보 폴더를 차례로 열어 본다. 쓰지 못한 폴더만 건너뛰고, 내용을 읽지 못한 폴더에서는 멈춘다
 * (다른 폴더로 넘어가면 망가진 기록을 알아채지 못하므로). 모두 쓰지 못했으면 null.
 * `skipped`: 쓰지 못해 건너뛴 폴더 수 (1 이상이면 이번에 새 폴더로 옮겨 간 것)
 */
export async function openFirstUsableAppFolder(
  roots: readonly string[],
  attempt: (root: string) => Promise<AppFolderAttempt>,
): Promise<{ root: string; outcome: 'connected' | 'unreadable'; skipped: number } | null> {
  let skipped = 0
  for (const root of roots) {
    const outcome = await attempt(root)
    if (outcome !== 'writeFailed') return { root, outcome, skipped }
    skipped++
  }
  return null
}

/** 지금 쓰는 기록 폴더 (‘파일로 저장’도 이 폴더의 ‘내보낸 파일’에 둔다). 기록 저장소가 연결할 때 정한다 */
let activeRoot = APP_RECORD_ROOT

export function activeAppRecordRoot(): string {
  return activeRoot
}

export function setActiveAppRecordRoot(root: string): void {
  activeRoot = root
}

/**
 * 공용 ‘문서’ 폴더에 쓸 권한. 안드로이드 10 이하는 저장 권한을 사용자에게 받아야 하고,
 * 11 이상은 이 앱이 만든 파일이면 권한 없이 쓴다 (Capacitor 파일 시스템 문서).
 */
export async function ensureNativeStoragePermission(): Promise<boolean> {
  try {
    if ((await Filesystem.checkPermissions()).publicStorage === 'granted') return true
    return (await Filesystem.requestPermissions()).publicStorage === 'granted'
  } catch {
    return false
  }
}

/** 바이트 → base64 (btoa는 글자 하나가 바이트 하나인 문자열을 받는다) */
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(binary)
}

export function base64ToBytes(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

/** 바이트를 `path`에 쓴다 (없는 상위 폴더는 만든다). 첫 조각은 새로 쓰고, 나머지는 이어 쓴다 */
export async function writeNativeBytes(
  fs: NativeFilesystem,
  path: string,
  directory: Directory,
  bytes: Uint8Array,
): Promise<void> {
  await fs.writeFile({ path, directory, data: bytesToBase64(bytes.subarray(0, NATIVE_CHUNK_BYTES)), recursive: true })
  for (let start = NATIVE_CHUNK_BYTES; start < bytes.length; start += NATIVE_CHUNK_BYTES) {
    await fs.appendFile({ path, directory, data: bytesToBase64(bytes.subarray(start, start + NATIVE_CHUNK_BYTES)) })
  }
}

/**
 * 안드로이드 앱의 기록 폴더 (`DirectoryFolder`처럼 `울림-설정.json`·`울림-기록.json`·`녹음/*.wav`를 둔다).
 * 웹과 같은 파일 모양이라, 기록 파일(zip)로 웹·아이폰과 주고받을 수 있다.
 * 안드로이드 11 이상은 이 앱이 만든 파일만 읽을 수 있어서, 앱을 지웠다 다시 깔면 예전 파일은 ‘기록 파일 불러오기’로 연다.
 */
export class NativeFolder implements RecordFolder {
  readonly name: string
  readonly #fs: NativeFilesystem
  readonly #directory: Directory
  readonly #root: string

  constructor(fs: NativeFilesystem = Filesystem, directory: Directory = Directory.Documents, root = APP_RECORD_ROOT) {
    this.#fs = fs
    this.#directory = directory
    this.#root = root
    this.name = appRecordFolderName(root)
  }

  /** ‘문서’ 안의 폴더 이름 (‘울림’, ‘울림-2’ …) */
  get root(): string {
    return this.#root
  }

  #full(path: string): string {
    splitPath(path)
    return `${this.#root}/${path}`
  }

  /** 있는지. 없으면 앱이 오류를 내므로(오류 문구는 기기마다 달라서) 먼저 확인한다 */
  async #exists(full: string): Promise<boolean> {
    try {
      await this.#fs.stat({ path: full, directory: this.#directory })
      return true
    } catch {
      return false
    }
  }

  async read(path: string): Promise<Blob | null> {
    const full = this.#full(path)
    if (!(await this.#exists(full))) return null
    const { data } = await this.#fs.readFile({ path: full, directory: this.#directory })
    return typeof data === 'string' ? new Blob([base64ToBytes(data)]) : data
  }

  /**
   * 같은 이름의 파일에 바로 덮어쓴다. 공용 ‘문서’ 폴더에서는 “임시 파일에 쓰고 → 원래 파일 지우고 → 이름 바꾸기”를 하면
   * 안드로이드의 미디어 목록(MediaProvider)이 뒤늦게 따라오다 어긋나서, 이 앱도 열 수 없는(EACCES) 파일이 생긴다 (2026-10-26 에뮬레이터 확인).
   * 기록 JSON은 작아 한 번에 쓰고, 녹음 WAV는 늘 새 이름에 쓴 뒤에야 기록에 올리므로, 중간에 멈춰도 기록이 반쪽이 되지 않는다.
   * 다시 설치한 뒤 예전 앱의 파일과 이름이 겹치면 여기서 오류가 난다 (기록 저장소가 다음 폴더를 열어 본다).
   */
  async write(path: string, data: Blob | string): Promise<void> {
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(await data.arrayBuffer())
    await writeNativeBytes(this.#fs, this.#full(path), this.#directory, bytes)
  }

  async remove(path: string): Promise<void> {
    const full = this.#full(path)
    if (await this.#exists(full)) await this.#fs.deleteFile({ path: full, directory: this.#directory })
  }

  async list(directory: string): Promise<string[]> {
    const full = this.#full(directory)
    if (!(await this.#exists(full))) return []
    const { files } = await this.#fs.readdir({ path: full, directory: this.#directory })
    return files.filter((file) => file.type === 'file').map((file) => file.name)
  }
}
