/**
 * 고른 기록 폴더의 연결 정보(폴더 핸들)를 이 브라우저(IndexedDB)에 둔다. 브라우저에 남는 것은 이 연결 정보뿐이고,
 * 기록 내용은 폴더에 있다. 다음에 열 때 같은 폴더에 다시 연결하는 데 쓴다 (브라우저가 허락을 다시 물을 수 있다).
 */
const DATABASE = 'ullim'
const STORE = 'handles'
const KEY = 'recordFolder'

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function run<T>(mode: IDBTransactionMode, action: (store: IDBObjectStore) => IDBRequest): Promise<T> {
  const database = await openDatabase()
  try {
    return await new Promise<T>((resolve, reject) => {
      const request = action(database.transaction(STORE, mode).objectStore(STORE))
      request.onsuccess = () => resolve(request.result as T)
      request.onerror = () => reject(request.error)
    })
  } finally {
    database.close()
  }
}

/** 저장해 둔 기록 폴더. 없거나 읽을 수 없으면 null */
export async function loadFolderHandle(): Promise<FileSystemDirectoryHandle | null> {
  try {
    const handle = await run<unknown>('readonly', (store) => store.get(KEY))
    return handle instanceof FileSystemDirectoryHandle ? handle : null
  } catch {
    return null
  }
}

/** 기록 폴더를 기억한다 (`null`이면 잊는다). 저장소가 막혀 있으면 이번 실행 동안만 연결된다 */
export async function saveFolderHandle(handle: FileSystemDirectoryHandle | null): Promise<void> {
  try {
    await run('readwrite', (store) => (handle === null ? store.delete(KEY) : store.put(handle, KEY)))
  } catch {
    // 사생활 보호 모드 등: 다음에 열 때 폴더를 다시 고르면 된다
  }
}
