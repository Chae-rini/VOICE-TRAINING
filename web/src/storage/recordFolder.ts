/**
 * 기록을 담는 곳. 경로는 `울림-설정.json`이나 `녹음/Ullim-20261025-2012.wav`처럼 한 단계 폴더까지만 쓴다.
 * - `DirectoryFolder`: 내가 고른 폴더 (컴퓨터의 Chrome·Edge, 안드로이드 Chrome)
 * - `MemoryFolder`: 페이지가 열려 있는 동안만 있는 폴더 (폴더를 고를 수 없는 브라우저, 테스트). 기록 파일(zip)로 저장·불러오기
 */
export interface RecordFolder {
  /** 화면에 보일 이름 (고른 폴더의 이름) */
  readonly name: string
  /** 없으면 null */
  read(path: string): Promise<Blob | null>
  write(path: string, data: Blob | string): Promise<void>
  remove(path: string): Promise<void>
  /** `directory` 폴더 안의 파일 이름들 (폴더가 없으면 빈 목록) */
  list(directory: string): Promise<string[]>
}

/** 경로를 [폴더, 파일 이름]으로. 두 단계보다 깊거나 `..`·빈 이름이면 오류 */
export function splitPath(path: string): [string | null, string] {
  const parts = path.split('/')
  if (parts.length > 2 || parts.some((part) => part === '' || part === '.' || part === '..' || part.includes('\\'))) {
    throw new Error(`기록 폴더에 쓸 수 없는 경로: ${path}`)
  }
  return parts.length === 2 ? [parts[0], parts[1]] : [null, parts[0]]
}

export class MemoryFolder implements RecordFolder {
  readonly #files = new Map<string, Blob>()

  constructor(readonly name = '이 페이지') {}

  async read(path: string): Promise<Blob | null> {
    splitPath(path)
    return this.#files.get(path) ?? null
  }

  async write(path: string, data: Blob | string): Promise<void> {
    splitPath(path)
    this.#files.set(path, typeof data === 'string' ? new Blob([data], { type: 'application/json' }) : data)
  }

  async remove(path: string): Promise<void> {
    this.#files.delete(path)
  }

  async list(directory: string): Promise<string[]> {
    const prefix = `${directory}/`
    return [...this.#files.keys()].filter((path) => path.startsWith(prefix)).map((path) => path.slice(prefix.length))
  }

  /** 담긴 모든 경로 (테스트·기록 파일 만들기용) */
  get paths(): string[] {
    return [...this.#files.keys()]
  }
}

function isNotFound(error: unknown): boolean {
  return error instanceof DOMException && (error.name === 'NotFoundError' || error.name === 'TypeMismatchError')
}

export class DirectoryFolder implements RecordFolder {
  constructor(readonly handle: FileSystemDirectoryHandle) {}

  get name(): string {
    return this.handle.name
  }

  async #directory(name: string | null, create: boolean): Promise<FileSystemDirectoryHandle | null> {
    if (name === null) return this.handle
    try {
      return await this.handle.getDirectoryHandle(name, { create })
    } catch (error) {
      if (isNotFound(error)) return null
      throw error
    }
  }

  async read(path: string): Promise<Blob | null> {
    const [directoryName, fileName] = splitPath(path)
    const directory = await this.#directory(directoryName, false)
    if (directory === null) return null
    try {
      return await (await directory.getFileHandle(fileName)).getFile()
    } catch (error) {
      if (isNotFound(error)) return null
      throw error
    }
  }

  async write(path: string, data: Blob | string): Promise<void> {
    const [directoryName, fileName] = splitPath(path)
    const directory = (await this.#directory(directoryName, true))!
    const file = await directory.getFileHandle(fileName, { create: true })
    // 브라우저는 임시 파일에 다 쓴 뒤 닫을 때 한 번에 바꿔 넣는다 (쓰다가 멈춰도 예전 파일은 남는다).
    const writable = await file.createWritable()
    try {
      await writable.write(data)
      await writable.close()
    } catch (error) {
      await writable.abort().catch(() => {})
      throw error
    }
  }

  async remove(path: string): Promise<void> {
    const [directoryName, fileName] = splitPath(path)
    const directory = await this.#directory(directoryName, false)
    try {
      await directory?.removeEntry(fileName)
    } catch (error) {
      if (!isNotFound(error)) throw error
    }
  }

  async list(directoryName: string): Promise<string[]> {
    const directory = await this.#directory(directoryName, false)
    if (directory === null) return []
    const names: string[] = []
    for await (const [name, entry] of directory.entries()) {
      if (entry.kind === 'file') names.push(name)
    }
    return names
  }
}
