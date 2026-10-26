<script lang="ts">
  import { settings } from '../model/settings.svelte'
  import { store } from '../storage/recordStore.svelte'

  /**
   * [기록] 탭의 ‘내 기록 저장 위치’: 기록 폴더 고르기·다시 연결·바꾸기·끊기, 기록 파일(zip)로 저장·불러오기.
   * 기록은 이 웹사이트가 아니라 내가 고른 폴더나 내가 저장한 파일에 남는다 (W6, 사용자 결정).
   */
  let fileInput: HTMLInputElement

  const status = $derived(store.status)
  const savedTime = $derived(
    store.savedAt === null ? null : store.savedAt.toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit' }),
  )

  function chooseImport() {
    fileInput.click()
  }

  function onFileChosen() {
    const file = fileInput.files?.[0]
    fileInput.value = ''
    if (file === undefined) return
    // 지금 값이 파일의 것으로 바뀌므로, 잃을 것이 있으면 먼저 묻는다
    const question =
      status.kind === 'connected'
        ? `고른 폴더의 ‘울림-설정.json’과 ‘울림-기록.json’이 ‘${file.name}’의 내용으로 바뀌어요. 계속할까요?`
        : store.unsaved
          ? `아직 저장하지 않은 바뀐 내용은 사라지고 ‘${file.name}’의 기록으로 바뀌어요. 계속할까요?`
          : null
    if (question !== null && !confirm(question)) return
    void store.importFile(file)
  }
</script>

<section class="card" aria-labelledby="storage-title">
  <h2 id="storage-title">내 기록 저장 위치</h2>
  <p class="secondary">
    {store.isApp
      ? '목표 범위·내 기준 목소리·내 모음 지도와 연습 기록은 휴대폰의 ‘문서/울림’ 폴더에 파일로 남아요. 울림은 기록을 어디로도 보내지 않아요.'
      : '목표 범위·내 기준 목소리·내 모음 지도와 연습 기록은 이 웹사이트가 아니라 내가 고른 곳에 파일로 남아요. 울림은 기록을 어디로도 보내지 않아요.'}
  </p>

  {#if store.isApp}
    <!-- 안드로이드 앱: 폴더를 고르지 않고 ‘문서/울림’에 바로 쓴다 (A2) -->
    {#if status.kind === 'connected'}
      <p class="state ok">✓ 휴대폰의 ‘{status.folderName}’ 폴더에 저장하고 있어요</p>
      {#if savedTime !== null}
        <p class="secondary small">마지막 저장 {savedTime}</p>
      {/if}
      <p class="secondary small">
        파일 앱의 ‘문서 › 울림’에서 볼 수 있고, 앱을 지워도 남아요. 앱을 다시 설치하면 예전 파일을 바로 읽지 못하니, 미리 ‘기록
        파일로 저장’해 두었다가 ‘기록 파일 불러오기’로 열어 주세요.
      </p>
    {:else}
      <p class="state warn">휴대폰의 ‘문서/울림’ 폴더를 아직 열지 못했어요</p>
      <div class="buttons">
        <button class="fill" onclick={() => store.connectAppFolder()} disabled={store.busy}>📁 다시 열기</button>
      </div>
    {/if}
  {:else if status.kind === 'connected'}
    <p class="state ok">✓ ‘{status.folderName}’ 폴더에 저장하고 있어요</p>
    {#if savedTime !== null}
      <p class="secondary small">마지막 저장 {savedTime}</p>
    {/if}
    <div class="buttons">
      <button onclick={() => store.chooseFolder()} disabled={store.busy}>다른 폴더로 바꾸기</button>
      <button class="plain" onclick={() => store.disconnect()} disabled={store.busy}>연결 끊기</button>
    </div>
  {:else if status.kind === 'needsPermission'}
    <p class="state warn">‘{status.folderName}’ 폴더에 다시 연결해야 해요</p>
    <p class="secondary small">
      브라우저가 이 폴더를 다시 써도 되는지 물어요. ‘허용’(있으면 ‘방문할 때마다 허용’)을 눌러 주세요.
    </p>
    <div class="buttons">
      <button class="fill" onclick={() => store.reconnect()} disabled={store.busy}>📁 다시 연결</button>
      <button onclick={() => store.chooseFolder()} disabled={store.busy}>다른 폴더 고르기</button>
    </div>
  {:else if status.kind === 'none'}
    <p class="state">아직 기록 폴더를 고르지 않았어요</p>
    <p class="secondary small">
      고른 폴더 안에 ‘울림-설정.json’과 ‘울림-기록.json’을 만들고, 남긴 녹음은 ‘녹음’ 폴더에 둬요. 다른 파일은 건드리지 않아요.
      ‘울림 기록’ 같은 새 폴더를 만들어 고르는 것을 권해요.
    </p>
    <div class="buttons">
      <button class="fill" onclick={() => store.chooseFolder()} disabled={store.busy}>📁 기록 폴더 고르기</button>
    </div>
  {:else}
    <p class="state">이 브라우저는 폴더에 바로 저장하지 못해요</p>
    <p class="secondary small">
      기록을 파일 하나(‘울림-기록-날짜.zip’)로 저장해 두고, 다음에 열 때 ‘기록 파일 불러오기’로 이어서 써요. 아이폰은 보통 ‘파일’
      앱의 ‘다운로드’ 폴더에 저장돼요.
    </p>
  {/if}

  {#if store.unsaved && status.kind !== 'connected'}
    <p class="warn" role="status">
      ⚠︎ 아직 파일로 남기지 않은 바뀐 내용이 있어요.
      {store.isApp
        ? '폴더를 다시 열면 저장돼요.'
        : status.kind === 'memory'
          ? '기록 파일로 저장해 주세요.'
          : status.kind === 'none'
            ? '기록 폴더를 고르면 저장돼요.'
            : '다시 연결하면 저장돼요.'}
    </p>
  {/if}

  <div class="buttons">
    <button class:fill={status.kind === 'memory'} onclick={() => store.exportFile()} disabled={store.busy}>
      ⬇︎ 기록 파일로 저장
    </button>
    <button onclick={chooseImport} disabled={store.busy}>⬆︎ 기록 파일 불러오기</button>
  </div>
  {#if store.isApp}
    <p class="secondary small">
      기록 파일은 ‘문서/울림/내보낸 파일’에 저장돼요. 다른 기기(아이폰 사파리 등)로 옮기거나 앱을 다시 설치할 때 써요.
    </p>
  {:else if status.kind !== 'memory'}
    <p class="secondary small">기록 파일은 다른 기기(아이폰 사파리 등)로 옮기거나 따로 보관할 때 써요.</p>
  {/if}

  {#if store.busy}
    <p class="secondary small" role="status">기록을 정리하는 중…</p>
  {:else if store.errorMessage !== null}
    <p class="warn" role="alert">{store.errorMessage}</p>
  {:else if store.infoMessage !== null}
    <p class="saved" role="status">{store.infoMessage}</p>
  {/if}

  {#if settings.isTemporary}
    <p class="secondary small">
      이 브라우저가 저장을 막고 있어서 화면 설정(문장 종류·들려줄 길이 등)과 폴더 연결은 이 페이지를 닫기 전까지만 기억돼요.
    </p>
  {/if}
</section>

<input bind:this={fileInput} type="file" accept=".zip,application/zip" hidden onchange={onFileChosen} />

<style>
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 0.85rem;
  }
  .card p {
    margin: 0;
  }
  h2 {
    margin: 0;
    font-size: 0.95rem;
  }
  .secondary {
    color: var(--secondary);
  }
  .small {
    font-size: 0.8rem;
  }
  .state {
    font-weight: 600;
  }
  .ok,
  .saved {
    color: var(--record);
  }
  .warn {
    color: var(--warning);
  }
  .buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .fill {
    background: var(--target);
    color: #ffffff;
  }
</style>
