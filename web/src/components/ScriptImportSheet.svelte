<script lang="ts">
  import { estimatedSecondsOf } from '../data/scripts'
  import { newRecordId } from '../model/records'
  import {
    COUNT_RANGE,
    DEFAULT_REQUEST,
    myScriptsFrom,
    parseScripts,
    scriptRequestPrompt,
    SECONDS_OPTIONS,
    STYLE_OPTIONS,
    type ScriptDraft,
    type ScriptRequest,
  } from '../model/scriptImport'
  import { copyText, shareText } from '../practice/sharing'
  import { store } from '../storage/recordStore.svelte'

  /**
   * AI 대본 가져오기 (iOS `ScriptImportView`, 2026-10-31~): ① 부탁 글을 만들어 AI 앱으로 보내고 ② AI가 쓴 답을 붙여넣어 ‘내 대본’에 남긴다.
   * 울림은 인터넷에 연결하지 않는다 (원칙 2). 부탁 글은 사용자가 공유 창에서 고른 앱으로만 나가거나 복사된다.
   * 창은 한 번 만들어 두고 열고 닫기만 해서, 열 때마다 붙여넣은 글과 미리 보기를 비운다.
   */
  let { open, onClose, onSaved }: { open: boolean; onClose: () => void; onSaved: () => void } = $props()

  let dialog: HTMLDialogElement
  let request: ScriptRequest = $state({ ...DEFAULT_REQUEST })
  let pasted = $state('')
  let drafts: ScriptDraft[] = $state([])
  let didCopy = $state(false)
  let requestMessage: string | null = $state(null)
  let pasteMessage: string | null = $state(null)
  let saving = $state(false)

  const prompt = $derived(scriptRequestPrompt(request))
  /**
   * 클립보드를 읽는 ‘붙여넣기’ 단추를 쓸 수 있는지. 안드로이드 앱의 웹뷰는 읽기를 늘 막아서(권한 denied, 2026-10-31 에뮬레이터 확인)
   * 단추를 숨기고 칸을 길게 눌러 붙여 넣게 한다 (휴대폰 기본 ‘붙여넣기’ 메뉴는 된다)
   */
  const canReadClipboard = !store.isApp && typeof navigator.clipboard?.readText === 'function'
  const canSave = $derived(drafts.length > 0 && !saving && drafts.every((draft) => draft.title.trim() !== ''))
  /** 남긴 대본이 어디에 남는지 (기록 폴더가 없으면 폴더를 고르거나 기록 파일로 저장해야 다음에도 남는다) */
  const whereSaved = $derived(
    store.status.kind === 'connected'
      ? store.isApp
        ? '[높이] 대본의 ‘내 대본’ 종류에 남아요. 휴대폰의 기록 폴더에 ‘울림-대본.json’으로 저장돼요.'
        : `[높이] 대본의 ‘내 대본’ 종류에 남아요. 기록 폴더 ‘${store.status.folderName}’에 ‘울림-대본.json’으로 저장돼요.`
      : store.isApp
        ? '[높이] 대본의 ‘내 대본’ 종류에 남아요. 기록 폴더를 열지 못해서 앱을 닫으면 사라져요.'
        : '[높이] 대본의 ‘내 대본’ 종류에 남아요. 기록 폴더를 고르거나 기록 파일로 저장해야 다음에도 남아요.',
  )

  $effect(() => {
    if (open && !dialog.open) {
      pasted = ''
      drafts = []
      didCopy = false
      requestMessage = null
      pasteMessage = null
      dialog.showModal()
    } else if (!open && dialog.open) {
      dialog.close()
    }
  })

  // 고른 조건이 바뀌면 부탁 글도 바뀌므로 ‘복사했어요’를 지운다
  function changeRequest(patch: Partial<ScriptRequest>) {
    request = { ...request, ...patch }
    didCopy = false
    requestMessage = null
  }

  async function share() {
    requestMessage = null
    switch (await shareText(prompt)) {
      case 'copied':
        requestMessage = '공유 창이 없어 부탁 글을 복사했어요. 쓰시는 AI 앱에 붙여 넣으세요.'
        didCopy = true
        break
      case 'failed':
        requestMessage = '부탁 글을 보내지 못했어요. 아래 ‘부탁 글 복사’를 눌러 주세요.'
        break
    }
  }

  async function copy() {
    didCopy = await copyText(prompt)
    requestMessage = didCopy ? null : '복사하지 못했어요. 부탁 글을 길게 눌러 직접 복사해 주세요.'
  }

  // 붙여넣은 글이 바뀌면 미리 보기를 새로 만든다 (고친 제목도 처음으로 돌아간다)
  function setPasted(text: string) {
    pasted = text
    drafts = parseScripts(text)
  }

  /** 클립보드의 글을 읽는다. 브라우저가 처음 한 번 허락을 물을 수 있고, 안 되면 칸에 직접 붙여 넣게 안내한다 */
  async function pasteFromClipboard() {
    pasteMessage = null
    try {
      const text = await navigator.clipboard.readText()
      if (text.trim() === '') {
        pasteMessage = '복사해 둔 글이 없어요. AI의 답을 먼저 복사해 주세요.'
        return
      }
      setPasted(text)
    } catch {
      pasteMessage = '여기서는 ‘붙여넣기’를 쓸 수 없어요. 아래 칸을 길게 눌러(컴퓨터는 Ctrl+V·⌘V) 붙여 넣어 주세요.'
    }
  }

  async function save() {
    if (!canSave) return
    saving = true
    try {
      await store.addScripts(myScriptsFrom($state.snapshot(drafts), new Date(), newRecordId))
    } finally {
      saving = false
    }
    onSaved()
    onClose()
  }
</script>

<dialog bind:this={dialog} oncancel={(event) => { event.preventDefault(); onClose() }} aria-labelledby="import-title">
  <header>
    <button class="plain" onclick={onClose}>닫기</button>
    <h2 id="import-title">AI 대본 가져오기</h2>
    <span></span>
  </header>

  <div class="content">
    <section>
      <h3>1. AI에게 부탁하기</h3>
      <div class="group">
        <label class="row">
          <span>편 수</span>
          <select value={request.count} onchange={(event) => changeRequest({ count: Number(event.currentTarget.value) })}>
            {#each Array.from({ length: COUNT_RANGE.max - COUNT_RANGE.min + 1 }, (_, i) => COUNT_RANGE.min + i) as count (count)}
              <option value={count}>{count}편</option>
            {/each}
          </select>
        </label>
        <label class="row">
          <span>한 편 길이</span>
          <select value={request.seconds} onchange={(event) => changeRequest({ seconds: Number(event.currentTarget.value) })}>
            {#each SECONDS_OPTIONS as seconds (seconds)}
              <option value={seconds}>약 {seconds}초</option>
            {/each}
          </select>
        </label>
        <label class="row">
          <span>말투</span>
          <select
            value={request.style ?? ''}
            onchange={(event) => changeRequest({ style: event.currentTarget.value === '' ? null : event.currentTarget.value })}
          >
            <option value="">섞어서</option>
            {#each STYLE_OPTIONS as style (style)}
              <option value={style}>{style}</option>
            {/each}
          </select>
        </label>
        <input
          type="text"
          value={request.topic}
          oninput={(event) => changeRequest({ topic: event.currentTarget.value })}
          placeholder="주제 (비워 두면 일상 장면)"
          aria-label="주제"
        />
        <button class="fill" onclick={share}>↗ AI에게 대본 부탁하기</button>
        <button onclick={copy}>{didCopy ? '✓ 복사했어요' : '부탁 글 복사'}</button>
      </div>
      {#if requestMessage !== null}
        <p class="note warning">{requestMessage}</p>
      {/if}
      <p class="note">
        부탁 글을 쓰시는 AI 앱에 보내거나 붙여 넣으세요. 울림은 인터넷에 연결하지 않아요. 보낸 내용은 고른 앱으로 전송돼요.
      </p>
    </section>

    <section>
      <h3>2. AI가 쓴 대본 붙여넣기</h3>
      <div class="group">
        {#if canReadClipboard}
          <button onclick={pasteFromClipboard}>📋 붙여넣기</button>
        {/if}
        <textarea value={pasted} oninput={(event) => setPasted(event.currentTarget.value)} rows="6" aria-label="AI가 쓴 대본"
        ></textarea>
      </div>
      {#if pasteMessage !== null}
        <p class="note warning">{pasteMessage}</p>
      {/if}
      <p class="note">
        {canReadClipboard
          ? 'AI의 답을 복사한 뒤 ‘붙여넣기’를 누르거나 위 칸에 붙여 넣으세요.'
          : 'AI의 답을 복사한 뒤 위 칸을 길게 눌러 붙여 넣으세요.'}
        ‘제목:’ 줄은 제목으로 쓰고, ‘---’ 줄로 나눈 글은 여러 편으로 가져와요.
      </p>
    </section>

    {#if drafts.length > 0}
      <section>
        <h3>미리 보기 · {drafts.length}편</h3>
        <ul class="drafts">
          {#each drafts as draft, index (index)}
            <li class="group">
              <input class="title" type="text" bind:value={draft.title} aria-label="제목" />
              <p class="text">{draft.text}</p>
              <div class="draft-footer">
                <span class="note">약 {Math.round(estimatedSecondsOf(draft.text))}초</span>
                <button class="plain small remove" onclick={() => drafts.splice(index, 1)}>빼기</button>
              </div>
            </li>
          {/each}
        </ul>
        <p class="note">제목을 눌러 고칠 수 있어요. 가져오지 않을 대본은 ‘빼기’로 빼세요.</p>
        <button class="fill" onclick={save} disabled={!canSave}>{drafts.length}편을 내 대본에 남기기</button>
        <p class="note">{whereSaved}</p>
      </section>
    {/if}
  </div>
</dialog>

<style>
  dialog {
    width: min(480px, calc(100vw - 32px));
    max-height: calc(100dvh - 48px);
    padding: 0;
    border: none;
    border-radius: 16px;
    background: var(--background);
    color: var(--text);
  }
  dialog::backdrop {
    background: rgb(0 0 0 / 0.4);
  }
  header {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--divider);
  }
  header button {
    justify-self: start;
  }
  h2 {
    margin: 0;
    font-size: 1rem;
  }
  h3 {
    margin: 0 0 8px;
    font-size: 0.85rem;
    color: var(--secondary);
    font-weight: 600;
  }
  .content {
    display: flex;
    flex-direction: column;
    gap: 20px;
    padding: 16px;
  }
  section {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .group {
    background: var(--card);
    border-radius: 12px;
    padding: 12px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
  }
  select {
    font: inherit;
    color: var(--target);
    background: transparent;
    border: none;
    padding: 4px 0;
  }
  input[type='text'],
  textarea {
    font: inherit;
    width: 100%;
    box-sizing: border-box;
    padding: 10px 12px;
    border: 1px solid var(--divider);
    border-radius: 10px;
    background: var(--background);
    color: var(--text);
  }
  textarea {
    resize: vertical;
    line-height: 1.5;
  }
  .note {
    margin: 0;
    color: var(--secondary);
    font-size: 0.8rem;
  }
  .warning {
    color: var(--warning);
  }
  button.fill {
    background: var(--target);
    color: #ffffff;
  }
  .drafts {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .title {
    font-weight: 600;
  }
  .text {
    margin: 0;
    font-size: 0.85rem;
    line-height: 1.5;
    white-space: pre-line;
    word-break: keep-all;
    overflow-wrap: break-word;
    display: -webkit-box;
    -webkit-line-clamp: 4;
    line-clamp: 4;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .draft-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .remove {
    color: var(--warning);
  }
</style>
