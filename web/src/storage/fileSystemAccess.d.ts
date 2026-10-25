// 파일 시스템 접근 API 중 TypeScript 기본 타입(lib.dom)에 아직 없는 부분.
// 컴퓨터의 Chrome·Edge와 안드로이드 Chrome에만 있어서 모두 선택(?)으로 둔다 (사파리·Firefox에는 없음).

interface FileSystemHandlePermissionDescriptor {
  mode?: 'read' | 'readwrite'
}

interface FileSystemHandle {
  queryPermission?(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>
  requestPermission?(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>
}

interface DirectoryPickerOptions {
  /** 같은 id를 쓰면 지난번에 고른 위치에서 시작한다 */
  id?: string
  mode?: 'read' | 'readwrite'
  startIn?: 'desktop' | 'documents' | 'downloads' | 'music' | FileSystemHandle
}

interface Window {
  showDirectoryPicker?(options?: DirectoryPickerOptions): Promise<FileSystemDirectoryHandle>
}
