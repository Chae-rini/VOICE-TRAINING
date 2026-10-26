import { Directory, type FileInfo } from '@capacitor/filesystem'
import { describe, expect, it } from 'vitest'
import {
  base64ToBytes,
  bytesToBase64,
  NATIVE_CHUNK_BYTES,
  NativeFolder,
  type NativeFilesystem,
} from '../src/storage/nativeFolder'
import { copyRecordFolder } from '../src/storage/openFolder'
import { MemoryFolder } from '../src/storage/recordFolder'

// A2 안드로이드 앱의 기록 폴더(‘문서/울림’). 실제 기기 대신 Capacitor 파일 시스템처럼 동작하는 가짜로 시험한다:
// 내용은 base64로만 주고받고, 없는 파일은 stat·deleteFile이 오류를 내고, 이름 바꾸기는 있는 파일을 덮어쓰지 않는다(덮어쓰는지는 기기마다 달라서 더 엄격한 쪽).

class FakeFilesystem implements NativeFilesystem {
  readonly files = new Map<string, Uint8Array>()
  writes = 0
  appends = 0

  #key(directory: Directory | undefined, path: string): string {
    return `${directory}:${path}`
  }

  #isDirectory(key: string): boolean {
    return [...this.files.keys()].some((file) => file.startsWith(`${key}/`))
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

  async rename({ from, to, directory, toDirectory }: { from: string; to: string; directory?: Directory; toDirectory?: Directory }) {
    const source = this.#key(directory, from)
    const target = this.#key(toDirectory ?? directory, to)
    const file = this.files.get(source)
    if (file === undefined) throw new Error('File does not exist')
    if (this.files.has(target)) throw new Error('Destination file already exists')
    this.files.delete(source)
    this.files.set(target, file)
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

  it('같은 파일을 다시 쓰면 바뀐다 (이름 바꾸기가 덮어쓰지 않는 기기에서도). 임시 파일은 남지 않고 목록에도 없다', async () => {
    const fs = new FakeFilesystem()
    const folder = new NativeFolder(fs)
    await folder.write('울림-기록.json', '첫째')
    await folder.write('울림-기록.json', '둘째')
    expect(await (await folder.read('울림-기록.json'))?.text()).toBe('둘째')
    expect([...fs.files.keys()].some((key) => key.endsWith('.tmp'))).toBe(false)

    // 쓰다가 멈춰 임시 파일이 남았어도 녹음 목록에는 보이지 않는다
    fs.files.set(`${Directory.Documents}:울림/녹음/a.wav.tmp`, new Uint8Array([1]))
    fs.files.set(`${Directory.Documents}:울림/녹음/a.wav`, new Uint8Array([1]))
    expect(await folder.list('녹음')).toEqual(['a.wav'])
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
