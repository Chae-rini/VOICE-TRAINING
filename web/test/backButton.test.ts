import { afterEach, describe, expect, it } from 'vitest'
import { closeOpenDialog, onBack, runBackHandlers } from '../src/platform/backButton'

// 1묶음 안드로이드 뒤로 버튼: 화면 위에 나중에 열린 것부터 받고, 아무도 안 받으면 false (그때 앱이 [높이]로 가거나 뒤로 간다).

const removers: (() => void)[] = []
afterEach(() => {
  while (removers.length > 0) removers.pop()!()
})
function register(handler: () => boolean): () => void {
  const remove = onBack(handler)
  removers.push(remove)
  return remove
}

/** 브라우저의 `<dialog>`처럼 ‘cancel’을 받고 닫히는 가짜 (시험은 브라우저 없이 돈다) */
class FakeDialog extends EventTarget {
  open = true
  close() {
    this.open = false
  }
}
function rootWith(...dialogs: FakeDialog[]): ParentNode {
  return { querySelectorAll: () => dialogs.filter((d) => d.open) } as unknown as ParentNode
}

describe('뒤로 버튼 처리 순서', () => {
  it('아무도 안 걸었으면 처리하지 않는다', () => {
    expect(runBackHandlers()).toBe(false)
  })

  it('나중에 건 것부터 묻고, 처리한 곳에서 멈춘다', () => {
    const calls: string[] = []
    register(() => (calls.push('목록'), true))
    register(() => (calls.push('메뉴'), true))
    expect(runBackHandlers()).toBe(true)
    expect(calls).toEqual(['메뉴'])
  })

  it('지금 해당 없으면(false) 그 아래로 넘긴다', () => {
    const calls: string[] = []
    register(() => (calls.push('자세히 화면'), true))
    register(() => (calls.push('닫힌 메뉴'), false))
    expect(runBackHandlers()).toBe(true)
    expect(calls).toEqual(['닫힌 메뉴', '자세히 화면'])
  })

  it('뗀 처리 함수는 더 묻지 않는다', () => {
    const remove = register(() => true)
    remove()
    expect(runBackHandlers()).toBe(false)
  })
})

describe('열린 창 닫기', () => {
  it('열린 창이 없으면 처리하지 않는다', () => {
    expect(closeOpenDialog(rootWith())).toBe(false)
  })

  it('맨 위(나중에 열린) 창만 닫는다', () => {
    const below = new FakeDialog()
    const top = new FakeDialog()
    expect(closeOpenDialog(rootWith(below, top))).toBe(true)
    expect(top.open).toBe(false)
    expect(below.open).toBe(true)
  })

  it('창이 닫기를 막으면(재는 중) 열어 두되 뒤로는 처리한 것으로 본다', () => {
    const measuring = new FakeDialog()
    measuring.addEventListener('cancel', (event) => event.preventDefault())
    expect(closeOpenDialog(rootWith(measuring))).toBe(true)
    expect(measuring.open).toBe(true)
  })
})
