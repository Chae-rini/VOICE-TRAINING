import { Directory, type FileInfo } from '@capacitor/filesystem'
import { describe, expect, it } from 'vitest'
import { EMPTY_VOICE_SETTINGS } from '../src/model/voiceSettings'
import {
  appRecordRoots,
  base64ToBytes,
  bytesToBase64,
  NATIVE_CHUNK_BYTES,
  NativeFolder,
  openFirstUsableAppFolder,
  type AppFolderAttempt,
  type NativeFilesystem,
} from '../src/storage/nativeFolder'
import { copyRecordFolder, openRecordFolder } from '../src/storage/openFolder'
import { MemoryFolder } from '../src/storage/recordFolder'

// A2 안드로이드 앱의 기록 폴더(‘문서/울림’). 실제 기기 대신 Capacitor 파일 시스템처럼 동작하는 가짜로 시험한다:
// 내용은 base64로만 주고받고, 없는 파일은 stat·deleteFile이 오류를 낸다. 이름 바꾸기는 없다 (공용 폴더에서 쓰면 미디어 목록이 어긋나서 쓰지 않는다).

class FakeFilesystem implements NativeFilesystem {
  readonly files = new Map<string, Uint8Array>()
  /** 다시 설치하기 전의 앱이 만든 파일: 이 앱에는 보이지 않고(안드로이드 11 이상), 같은 이름으로 쓸 수도 없다 */
  readonly foreign = new Set<string>()
  writes = 0
  appends = 0
  deletes = 0

  #key(directory: Directory | undefined, path: string): string {
    return `${directory}:${path}`
  }

  #isDirectory(key: string): boolean {
    return [...this.files.keys(), ...this.foreign].some((file) => file.startsWith(`${key}/`))
  }

  async stat({ path, directory }: { path: string; directory?: Directory }) {
    const key = this.#key(directory, path)
    const file = this.files.get(key)
    if (file === undefined && !this.#isDirectory(key)) throw new Error('File does not exist')
    const info: FileInfo = { name: path.split('/').pop()!, type: file ? 'file' : 'directory', size: file?.length ?? 0, mtime: 0, uri: key }
    return info
  }

  async readFile({ path, directory }: { path: string; directory?: Directory }) {
    const file = this.files.get(this.#key(directory, path))
    if (file === undefined) throw new Error('File does not exist')
    return { data: bytesToBase64(file) }
  }

  async writeFile({ path, directory, data, recursive }: { path: string; directory?: Directory; data: string | Blob; recursive?: boolean }) {
    if (typeof data !== 'string') throw new Error('Blob data is only supported on Web')
    if (this.foreign.has(this.#key(directory, path))) throw new Error('EEXIST (File exists)')
    const parent = path.split('/').slice(0, -1).join('/')
    if (!recursive && parent !== '' && !this.#isDirectory(this.#key(directory, parent))) throw new Error('Parent folder does not exist')
    this.files.set(this.#key(directory, path), base64ToBytes(data))
    this.writes++
    return { uri: this.#key(directory, path) }
  }

  async appendFile({ path, directory, data }: { path: string; directory?: Directory; data: string | Blob }) {
    if (typeof data !== 'string') throw new Error('Blob data is only supported on Web')
    const key = this.#key(directory, path)
    const before = this.files.get(key) ?? new Uint8Array()
    const added = base64ToBytes(data)
    const joined = new Uint8Array(before.length + added.length)
    joined.set(before)
    joined.set(added, before.length)
    this.files.set(key, joined)
    this.appends++
  }

  async deleteFile({ path, directory }: { path: string; directory?: Directory }) {
    if (!this.files.delete(this.#key(directory, path))) throw new Error('File does not exist')
    this.deletes++
  }

  async readdir({ path, directory }: { path: string; directory?: Directory }) {
    const prefix = `${this.#key(directory, path)}/`
    const names = new Set<string>()
    for (const key of this.files.keys()) {
      if (key.startsWith(prefix)) names.add(key.slice(prefix.length).split('/')[0])
    }
    const files = [...names].map((name) => ({
      name,
      type: this.files.has(prefix + name) ? ('file' as const) : ('directory' as const),
      size: 0,
      mtime: 0,
      uri: prefix + name,
    }))
    return { files }
  }

}

function randomBytes(length: number, seed = 1): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(length)
  let state = seed
  for (let i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) >>> 0
    bytes[i] = state >>> 24
  }
  return bytes
}

describe('base64 (앱으로 넘기는 글자)', () => {
  it('조각 경계 근처 길이도 그대로 되돌아온다', () => {
    for (const length of [0, 1, 2, 3, 0x7fff, 0x8000, 0x8001, 100_000]) {
      const bytes = randomBytes(length, length + 7)
      expect(base64ToBytes(bytesToBase64(bytes))).toEqual(bytes)
    }
  })

  it('한 번에 넘기는 크기는 3의 배수라 조각 사이에 채움 글자(=)가 없다', () => {
    expect(NATIVE_CHUNK_BYTES % 3).toBe(0)
    expect(bytesToBase64(randomBytes(NATIVE_CHUNK_BYTES))).not.toContain('=')
  })
})

describe('NativeFolder (휴대폰의 ‘문서/울림’)', () => {
  it('글(설정 JSON)을 쓰고 읽는다: 공용 문서 폴더의 ‘울림’ 아래에, 한글 그대로', async () => {
    const fs = new FakeFilesystem()
    const folder = new NativeFolder(fs)
    await folder.write('울림-설정.json', '{"목표":"140~180 Hz"}')
    expect([...fs.files.keys()]).toEqual([`${Directory.Documents}:울림/울림-설정.json`])
    expect(await (await folder.read('울림-설정.json'))?.text()).toBe('{"목표":"140~180 Hz"}')
    expect(folder.name).toBe('문서/울림')
  })

  it('큰 녹음은 나눠 쓴다: 첫 조각은 새로 쓰고 나머지는 이어 쓴다. 다시 읽으면 바이트가 같다', async () => {
    const fs = new FakeFilesystem()
    const folder = new NativeFolder(fs)
    const wav = randomBytes(NATIVE_CHUNK_BYTES * 2 + 1234)
    await folder.write('녹음/Ullim-20261026-2130.wav', new Blob([wav]))
    expect(fs.writes).toBe(1)
    expect(fs.appends).toBe(2)
    const read = await folder.read('녹음/Ullim-20261026-2130.wav')
    expect(new Uint8Array(await read!.arrayBuffer())).toEqual(wav)
  })

  it('같은 파일을 다시 쓰면 그 자리에 덮어쓴다: 지우거나 임시 파일을 만들지 않는다 (공용 폴더의 미디어 목록이 어긋나지 않게)', async () => {
    const fs = new FakeFilesystem()
    const folder = new NativeFolder(fs)
    await folder.write('울림-기록.json', '첫째')
    await folder.write('울림-기록.json', '둘째')
    expect(await (await folder.read('울림-기록.json'))?.text()).toBe('둘째')
    expect(fs.deletes).toBe(0)
    expect([...fs.files.keys()]).toEqual([`${Directory.Documents}:울림/울림-기록.json`])
  })

  it('없는 파일은 null, 없는 폴더의 목록은 빈 목록, 없는 파일 지우기는 오류 없이 넘어간다', async () => {
    const folder = new NativeFolder(new FakeFilesystem())
    expect(await folder.read('울림-설정.json')).toBeNull()
    expect(await folder.list('녹음')).toEqual([])
    await expect(folder.remove('녹음/없는.wav')).resolves.toBeUndefined()
  })

  it('지우기: 녹음 파일만 지우고 다른 파일은 그대로', async () => {
    const folder = new NativeFolder(new FakeFilesystem())
    await folder.write('녹음/a.wav', new Blob([new Uint8Array([1, 2, 3])]))
    await folder.write('녹음/b.wav', new Blob([new Uint8Array([4])]))
    await folder.remove('녹음/a.wav')
    expect(await folder.list('녹음')).toEqual(['b.wav'])
  })

  it('웹 기록 폴더와 같은 규칙: 두 단계보다 깊거나 ..가 든 경로는 쓰지 않는다', async () => {
    const folder = new NativeFolder(new FakeFilesystem())
    await expect(folder.write('../밖.json', 'x')).rejects.toThrow()
    await expect(folder.write('녹음/안/깊이.wav', 'x')).rejects.toThrow()
  })

  it('기록 파일(zip)에서 푼 폴더를 그대로 옮겨 담는다 (웹·앱이 같은 파일 모양)', async () => {
    const source = new MemoryFolder()
    await source.write('울림-설정.json', '{"app":"ullim"}')
    await source.write('울림-기록.json', '{"app":"ullim","kind":"records"}')
    await source.write('녹음/Ullim-20261026-2130.wav', new Blob([randomBytes(5000)]))
    const folder = new NativeFolder(new FakeFilesystem())
    await copyRecordFolder(source, folder)
    expect(await (await folder.read('울림-기록.json'))?.text()).toBe('{"app":"ullim","kind":"records"}')
    expect(await folder.list('녹음')).toEqual(['Ullim-20261026-2130.wav'])
  })
})

describe('다시 설치한 뒤: ‘울림’을 못 쓰면 ‘울림-2’로 (2026-10-26 사용자 결정 ①)', () => {
  it('열어 볼 순서: 울림, 울림-2 … 울림-9. 마지막으로 쓴 폴더를 먼저, 모르는 이름은 무시', () => {
    expect(appRecordRoots(null)).toEqual(['울림', '울림-2', '울림-3', '울림-4', '울림-5', '울림-6', '울림-7', '울림-8', '울림-9'])
    expect(appRecordRoots('울림-2').slice(0, 3)).toEqual(['울림-2', '울림', '울림-3'])
    expect(appRecordRoots('../밖')[0]).toBe('울림')
    expect(new NativeFolder(new FakeFilesystem(), Directory.Documents, '울림-2').name).toBe('문서/울림-2')
  })

  it('쓰지 못한 폴더만 건너뛰고, 내용을 읽지 못한 폴더에서는 멈춘다 (망가진 기록을 가리지 않게)', async () => {
    const outcomes: Record<string, AppFolderAttempt> = { 울림: 'writeFailed', '울림-2': 'unreadable', '울림-3': 'connected' }
    const tried: string[] = []
    const result = await openFirstUsableAppFolder(['울림', '울림-2', '울림-3'], async (root) => {
      tried.push(root)
      return outcomes[root]
    })
    expect(result).toEqual({ root: '울림-2', outcome: 'unreadable', skipped: 1 })
    expect(tried).toEqual(['울림', '울림-2'])
    expect(await openFirstUsableAppFolder(['울림', '울림-2'], async () => 'writeFailed')).toBeNull()
  })

  it('예전 앱의 파일이 있는 ‘울림’은 쓰지 못해 ‘울림-2’에 새로 만든다. 예전 파일은 건드리지 않는다', async () => {
    const fs = new FakeFilesystem()
    const old = [`${Directory.Documents}:울림/울림-설정.json`, `${Directory.Documents}:울림/울림-기록.json`]
    old.forEach((key) => fs.foreign.add(key))
    const attempt = async (root: string): Promise<AppFolderAttempt> => {
      try {
        const opened = await openRecordFolder(new NativeFolder(fs, Directory.Documents, root), EMPTY_VOICE_SETTINGS, new Set())
        return opened.ok ? 'connected' : 'unreadable'
      } catch {
        return 'writeFailed'
      }
    }
    const result = await openFirstUsableAppFolder(appRecordRoots(null), attempt)
    expect(result).toEqual({ root: '울림-2', outcome: 'connected', skipped: 1 })
    expect(fs.files.has(`${Directory.Documents}:울림-2/울림-설정.json`)).toBe(true)
    expect(fs.files.has(`${Directory.Documents}:울림-2/울림-기록.json`)).toBe(true)
    expect([...fs.foreign]).toEqual(old)
    // ‘울림’에는 아무것도 새로 만들지 않았다
    expect([...fs.files.keys()].some((key) => key.startsWith(`${Directory.Documents}:울림/`))).toBe(false)
  })
})
