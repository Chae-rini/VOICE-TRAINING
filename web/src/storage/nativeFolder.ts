import { Directory, Filesystem, type FilesystemPlugin } from '@capacitor/filesystem'
import { splitPath, type RecordFolder } from './recordFolder'

/** 쓰는 파일 시스템 기능만 (시험할 때 가짜를 끼운다) */
export type NativeFilesystem = Pick<
  FilesystemPlugin,
  'readFile' | 'writeFile' | 'appendFile' | 'deleteFile' | 'readdir' | 'stat' | 'rename'
>

/**
 * [byte] 한 번에 앱으로 넘기는 크기. 안드로이드에는 파일 내용을 base64 글자로만 넘길 수 있어서(Blob은 웹에서만),
 * 3분 녹음(약 17 MB)을 한 번에 넘기지 않고 나눠 이어 쓴다. 3의 배수라 조각마다 base64 끝에 채움 글자(=)가 붙지 않는다.
 */
export const NATIVE_CHUNK_BYTES = 768 * 1024

/** 휴대폰의 기록 폴더: 공용 ‘문서’ 폴더 안의 ‘울림’ (파일 앱에서 보이고, 앱을 지워도 남는다) */
export const APP_RECORD_ROOT = '울림'
export const APP_RECORD_FOLDER_NAME = '문서/울림'

/** 쓰다가 멈춰도 원래 파일이 남게, 임시 파일에 다 쓴 뒤 바꿔 넣는다 */
const TEMP_SUFFIX = '.tmp'

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
  readonly name = APP_RECORD_FOLDER_NAME
  readonly #fs: NativeFilesystem
  readonly #directory: Directory
  readonly #root: string

  constructor(fs: NativeFilesystem = Filesystem, directory: Directory = Directory.Documents, root = APP_RECORD_ROOT) {
    this.#fs = fs
    this.#directory = directory
    this.#root = root
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

  async write(path: string, data: Blob | string): Promise<void> {
    const full = this.#full(path)
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(await data.arrayBuffer())
    const temp = full + TEMP_SUFFIX
    await writeNativeBytes(this.#fs, temp, this.#directory, bytes)
    // 이름 바꾸기가 있는 파일을 덮어쓰는지는 기기마다 달라서, 원래 파일을 지운 뒤 바꾼다 (그 사이에 멈추면 임시 파일이 남는다)
    if (await this.#exists(full)) await this.#fs.deleteFile({ path: full, directory: this.#directory })
    await this.#fs.rename({ from: temp, to: full, directory: this.#directory, toDirectory: this.#directory })
  }

  async remove(path: string): Promise<void> {
    const full = this.#full(path)
    if (await this.#exists(full)) await this.#fs.deleteFile({ path: full, directory: this.#directory })
  }

  async list(directory: string): Promise<string[]> {
    const full = this.#full(directory)
    if (!(await this.#exists(full))) return []
    const { files } = await this.#fs.readdir({ path: full, directory: this.#directory })
    return files.filter((file) => file.type === 'file' && !file.name.endsWith(TEMP_SUFFIX)).map((file) => file.name)
  }
}
