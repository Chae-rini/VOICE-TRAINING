<script lang="ts">
  import type { PhraseEndingAnalysis } from '../dsp/phraseEnding'
  import { PitchSummary } from '../dsp/pitchSummary'
  import { session } from '../practice/session.svelte'
  import { copyText, saveTake, shareFeedback } from '../practice/sharing'
  import type { RecordedTake } from '../practice/take'
  import { store } from '../storage/recordStore.svelte'
  import PhraseEndingList from './PhraseEndingList.svelte'

  /**
   * 마지막 녹음(방금 녹음 또는 불러온 파일)의 피치 요약 카드 (iOS `RecordingSummaryView`).
   * "AI에게 피드백 받기"는 요약(원하면 녹음 파일도)을 브라우저 공유 창에 넘기고, 보낼 앱은 사용자가 고른다.
   * "파일로 저장"은 녹음을 WAV로 이 기기에 내려받는다. "기록에 남기기"는 소리와 요약·메모를 내 기록 폴더(또는 기록 파일)에 남긴다.
   * 앱 자체는 인터넷으로 아무것도 보내지 않는다. 숫자 아래에는 구절별 문장 끝 요약(`PhraseEndingList`)을 둔다.
   */
  let {
    take,
    summary,
    phraseEndings,
  }: { take: RecordedTake; summary: PitchSummary; phraseEndings: PhraseEndingAnalysis } = $props()

  let isShareMenuOpen = $state(false)
  let message: string | null = $state(null)
  let didCopy = $state(false)
  let memoDialog: HTMLDialogElement
  let memo = $state('')
  let saveFailed = $state(false)

  const connectedFolder = $derived(store.status.kind === 'connected' ? store.status.folderName : null)
  /** 남겼지만 아직 폴더·기록 파일에 쓰지 않았는지 (폴더를 고르면 저절로 옮겨지고 이 안내도 사라진다) */
  const isPending = $derived(session.isLastTakeSaved && (connectedFolder === null || store.unsaved))

  function askMemo() {
    memo = ''
    memoDialog.showModal()
  }

  async function saveToRecords() {
    memoDialog.close()
    saveFailed = (await session.saveLastTake(memo.trim())) === 'failed'
  }

  // 녹음이 바뀌면 안내를 지운다
  $effect(() => {
    void take.id
    didCopy = false
    message = null
    saveFailed = false
  })

  async function share(includesAudio: boolean) {
    isShareMenuOpen = false
    const result = await shareFeedback(take, summary, includesAudio, phraseEndings)
    message =
      result === 'copied'
        ? includesAudio
          ? '이 브라우저는 녹음 파일을 함께 넘길 수 없어서 요약만 복사했어요. 원하는 AI 앱에 붙여 넣으세요.'
          : '이 브라우저에는 공유 창이 없어서 요약을 복사했어요. 원하는 AI 앱에 붙여 넣으세요.'
        : result === 'failed'
          ? '보내지 못했어요. ‘요약 복사’를 눌러 붙여 넣어 주세요.'
          : null
  }

  /** 녹음을 WAV로 저장한다 (웹은 내려받기, 앱은 ‘문서/울림/내보낸 파일’) */
  async function saveWav() {
    try {
      const savedPath = await saveTake(take)
      message = savedPath === null ? null : `‘${savedPath}’에 저장했어요.`
    } catch {
      message = '파일로 저장하지 못했어요. 저장 공간을 확인해 주세요.'
    }
  }

  async function copy() {
    didCopy = await copyText(summary.feedbackRequest(take.title, false, phraseEndings))
    message = didCopy ? null : '복사하지 못했어요. 브라우저가 붙여 넣기 권한을 막았을 수 있어요.'
  }
</script>

<section class="card" aria-label="마지막 녹음 요약">
  <div class="header">
    <span class="title">{take.title}</span>
    <span class="duration">{PitchSummary.durationLabel(summary.duration)}</span>
  </div>

  <dl class="stats">
    <div><dt>중앙</dt><dd>{Math.round(summary.median)} Hz</dd></div>
    <div><dt>범위</dt><dd>{Math.round(summary.p10)}–{Math.round(summary.p90)} Hz</dd></div>
    <div>
      <dt>목표 범위 안</dt>
      <dd>{summary.inTargetFraction === null ? '–' : `${Math.round(summary.inTargetFraction * 100)}%`}</dd>
    </div>
  </dl>

  <PhraseEndingList analysis={phraseEndings} takeStart={take.startTime} />

  <div class="actions">
    <button class="record" onclick={askMemo} disabled={session.isLastTakeSaved || session.savingTake}>
      {session.savingTake ? '남기는 중…' : isPending ? '✓ 기록에 담았어요' : session.isLastTakeSaved ? '✓ 기록에 남겼어요' : '🗂 기록에 남기기'}
    </button>
    <button onclick={saveWav}>⤓ 파일로 저장</button>
  </div>

  <div class="actions">
    <div class="menu">
      <button class="share" onclick={() => (isShareMenuOpen = !isShareMenuOpen)} aria-expanded={isShareMenuOpen}>
        ⇪ AI에게 피드백 받기
      </button>
      {#if isShareMenuOpen}
        <div class="menu-items" role="menu">
          <button role="menuitem" onclick={() => share(false)}>요약 글만 보내기</button>
          <button role="menuitem" onclick={() => share(true)}>녹음 파일과 함께 보내기</button>
        </div>
      {/if}
    </div>
    <button onclick={copy}>{didCopy ? '✓ 복사했어요' : '요약 복사'}</button>
  </div>

  {#if message !== null}
    <p class="message" role="status">{message}</p>
  {/if}
  {#if saveFailed}
    <p class="message warning" role="alert">기록을 저장하지 못했어요. 저장 공간이나 기록 폴더를 확인해 주세요.</p>
  {:else if isPending}
    <p class="message pending" role="status">
      기록에 담았어요. 기록 폴더를 고르거나 [기록]에서 ‘기록 파일로 저장’을 해야 파일로 남아요.
    </p>
  {/if}

  <dialog bind:this={memoDialog} aria-labelledby="save-title">
    <h2 id="save-title">기록에 남기기</h2>
    <p>
      {connectedFolder !== null
        ? `이 녹음의 소리(WAV)와 요약을 ‘${connectedFolder}’ 폴더에 남겨요. 나중에 [기록]에서 날짜별로 다시 듣고 비교할 수 있어요.`
        : '이 녹음의 소리(WAV)와 요약을 기록에 담아요. 기록 폴더를 고르거나 ‘기록 파일로 저장’을 해야 파일로 남아요.'}
    </p>
    <input
      type="text"
      bind:value={memo}
      placeholder="메모 (안 써도 돼요)"
      maxlength="200"
      aria-label="메모"
      onkeydown={(event) => {
        if (event.key === 'Enter' && !event.isComposing) void saveToRecords()
      }}
    />
    <div class="dialog-buttons">
      <button class="plain" onclick={() => memoDialog.close()}>취소</button>
      <button class="record-fill" onclick={saveToRecords}>남기기</button>
    </div>
  </dialog>

  <p class="caption">
    ‘녹음 파일과 함께’는 파일을 받는 앱만 보여요. 원하는 앱이 없으면 ‘요약 복사’ 후 붙여 넣으세요. 보낸 내용은 고른 앱으로
    전송돼요.
    {store.isApp
      ? `‘파일로 저장’은 WAV 파일을 휴대폰의 ‘${store.appExportFolder}’에 저장해요.`
      : '‘파일로 저장’은 WAV 파일을 이 기기에 내려받아요 (브라우저에 따라 저장할 곳을 물어요).'}
  </p>
</section>

<style>
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .header {
    display: flex;
    justify-content: space-between;
    gap: 8px;
  }
  .title {
    font-weight: 600;
    font-size: 0.95rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .duration {
    color: var(--secondary);
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }
  .stats {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    margin: 0;
  }
  dt {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  dd {
    margin: 2px 0 0;
    font-weight: 500;
    font-size: 0.95rem;
    font-variant-numeric: tabular-nums;
  }
  .record {
    color: var(--record);
  }
  dialog {
    width: min(420px, calc(100vw - 32px));
    padding: 16px;
    border: none;
    border-radius: 16px;
    background: var(--background);
    color: var(--text);
    box-sizing: border-box;
  }
  dialog::backdrop {
    background: rgb(0 0 0 / 0.4);
  }
  dialog h2 {
    margin: 0 0 8px;
    font-size: 1rem;
  }
  dialog p {
    margin: 0 0 12px;
    color: var(--secondary);
    font-size: 0.85rem;
  }
  dialog input {
    width: 100%;
    box-sizing: border-box;
    padding: 10px 12px;
    border: 1px solid var(--divider);
    border-radius: 10px;
    background: var(--card);
    color: var(--text);
    font: inherit;
  }
  .dialog-buttons {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    margin-top: 14px;
  }
  .record-fill {
    background: var(--record);
    color: var(--background);
    font-weight: 600;
  }
  .actions {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }
  .menu {
    position: relative;
  }
  .share {
    background: var(--target);
    color: #ffffff;
  }
  .menu-items {
    position: absolute;
    left: 0;
    top: calc(100% + 6px);
    min-width: 220px;
    padding: 6px;
    border-radius: 12px;
    background: var(--background);
    box-shadow: 0 8px 30px rgb(0 0 0 / 0.25);
    display: flex;
    flex-direction: column;
    z-index: 5;
  }
  .menu-items button {
    background: none;
    color: var(--text);
    text-align: left;
    border-radius: 8px;
  }
  .menu-items button:hover {
    background: var(--fill);
  }
  .message {
    margin: 0;
    color: var(--record);
    font-size: 0.8rem;
  }
  .message.warning,
  .message.pending {
    color: var(--warning);
  }
  .caption {
    margin: 0;
    color: var(--secondary);
    font-size: 0.7rem;
  }
</style>
