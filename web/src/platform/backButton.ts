/**
 * 안드로이드 ‘뒤로’ 버튼을 화면 안에서 먼저 받는 곳들 (앱에서만 쓰인다).
 * 웹 화면은 주소가 바뀌지 않는 한 화면이라, 그대로 두면 자세히 화면에서 뒤로를 눌러도 앱이 통째로 닫힌다 (2026-10-26 에뮬레이터 확인).
 * 화면 조각(자세히 화면, 메뉴 등)이 열려 있는 동안 처리 함수를 걸어 두고, 처리했으면 true를 돌려준다.
 */
export type BackHandler = () => boolean

const handlers: BackHandler[] = []

/** 처리 함수를 건다. 돌려받은 함수를 부르면 뗀다 (Svelte `$effect`의 정리 함수로 쓰기 좋게) */
export function onBack(handler: BackHandler): () => void {
  handlers.push(handler)
  return () => {
    const index = handlers.lastIndexOf(handler)
    if (index >= 0) handlers.splice(index, 1)
  }
}

/** 나중에 건 것(화면 위에 열린 것)부터 묻는다. 누가 처리했으면 true */
export function runBackHandlers(): boolean {
  for (let i = handlers.length - 1; i >= 0; i--) {
    if (handlers[i]()) return true
  }
  return false
}

/** 열린 창(`<dialog>`)이 있으면 닫는다. 창이 닫기를 막으면(예: 재는 중) 닫지 않지만 뒤로는 처리한 것으로 본다 */
export function closeOpenDialog(root: ParentNode = document): boolean {
  const dialogs = [...root.querySelectorAll('dialog[open]')]
  const dialog = dialogs.at(-1) as HTMLDialogElement | undefined
  if (dialog === undefined) return false
  // 안드로이드 뒤로 = 키보드 Esc와 같게: ‘cancel’을 보내고, 창이 막지 않았으면 닫는다
  const cancel = new Event('cancel', { cancelable: true })
  if (dialog.dispatchEvent(cancel)) dialog.close()
  return true
}
