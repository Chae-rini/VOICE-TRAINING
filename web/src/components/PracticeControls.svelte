<script lang="ts">
  import { processingNotice } from '../audio/processing'
  import { GraphWindow } from '../dsp/graphWindow'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'
  import DurationControl from './DurationControl.svelte'
  import { navigation } from './navigation.svelte'

  /**
   * 화면 아래의 연습 조작 (iOS `PracticeControlsView`). [높이]·[모음] 화면이 같은 것을 쓴다.
   * - 쉬는 중: [녹음 불러오기] [▶ 마지막 녹음] [반복 루프 재생] → 정지할 때까지 녹음이 이어진다
   * - 녹음 중: [정지] [지금 들어보기] → 최근 녹음을 들려주고, 끝나면 자동으로 다시 녹음
   * - 듣는 중: [정지] [건너뛰기]
   */
  const isDev = import.meta.env.DEV
  let fileInput: HTMLInputElement

  const phase = $derived(session.phase)
  const notice = $derived(phase.kind === 'recording' ? processingNotice(session.processing) : null)

  const statusText = $derived.by(() => {
    switch (phase.kind) {
      case 'recording':
        return { text: `녹음 중 · ${phase.round}번째`, time: GraphWindow.timeLabel(session.elapsed), tone: 'recording' }
      case 'listening':
        return { text: `방금 녹음 듣는 중 · ${phase.round}번째`, time: GraphWindow.timeLabel(session.remaining), tone: 'voice' }
      case 'countdown':
        return { text: `숨 고르기 · 곧 ${phase.nextRound}번째 녹음`, time: GraphWindow.timeLabel(session.remaining), tone: 'plain' }
      case 'replaying':
        return {
          text: `‘${session.lastTake?.title ?? '마지막 녹음'}’ 듣는 중`,
          time: GraphWindow.timeLabel(session.remaining),
          tone: 'voice',
        }
      case 'measuring':
        return {
          text: session.measuringVowel !== null ? `‘${session.measuringVowel}’ 길게 내는 중` : '내 목소리 재는 중',
          time: GraphWindow.timeLabel(session.remaining),
          tone: 'reference',
        }
      case 'idle':
        return null
    }
  })

  function start(testTone = false) {
    void session.start(testTone ? { kind: 'testTone', testToneHz: 180 } : { kind: 'mic' }, settings.practiceDuration)
  }

  function openFilePicker() {
    // 고른 녹음을 바로 들려주려면, 누른 그때 소리를 준비해 둬야 한다.
    session.prepareAudio()
    fileInput.click()
  }

  function onFileChosen() {
    const file = fileInput.files?.[0]
    fileInput.value = ''
    if (file) void session.importFile(file)
  }
</script>

<div class="bottom">
  {#if session.restMessage !== null}
    <p class="rest" role="status">☕︎ {session.restMessage}</p>
  {/if}
  <div class="status">
    {#if statusText !== null}
      <span class={`phase ${statusText.tone}`}>
        <span class="dot" aria-hidden="true"></span>{statusText.text}
      </span>
      <span class="time">{statusText.time}</span>
    {:else}
      {#if session.busy === 'analyzing'}
        <span class="info">녹음을 분석하는 중…</span>
      {:else if session.errorMessage !== null && !navigation.baselineSheetOpen}
        <span class="error" role="alert">{session.errorMessage}</span>
      {:else if session.infoMessage !== null}
        <span class="info record">{session.infoMessage}</span>
      {:else}
        <span></span>
      {/if}
      <DurationControl locked={session.isRunning} />
    {/if}
  </div>
  {#if notice !== null}
    <p class="warning">{notice}</p>
  {/if}
  <div class="buttons">
    {#if phase.kind === 'idle'}
      <button class="icon" onclick={openFilePicker} disabled={session.isRunning} aria-label="녹음 불러오기">📁</button>
      {#if session.lastTake !== null}
        <button class="icon" onclick={() => session.replayLastTake()} disabled={session.isRunning} aria-label="마지막 녹음 듣기">▶</button>
      {/if}
      <button class="action" onclick={() => start()} disabled={session.isRunning}>
        {session.busy === 'starting' ? '켜는 중…' : '🔁 반복 루프 재생'}
      </button>
      {#if isDev}
        <button class="dev" onclick={() => start(true)} disabled={session.isRunning} aria-label="테스트 음으로 반복 루프 (개발용)">
          테스트 음
        </button>
      {/if}
    {:else if phase.kind === 'recording'}
      <button class="stop" onclick={() => session.stop()}>■ 정지</button>
      <button class="action" onclick={() => session.listenNow()}>▶ 지금 들어보기</button>
    {:else if phase.kind === 'listening'}
      <button class="stop" onclick={() => session.stop()}>■ 정지</button>
      <button class="action" onclick={() => session.skipListening()}>⏭ 건너뛰기</button>
    {:else}
      <button class="stop wide" onclick={() => session.stop()}>■ 정지</button>
    {/if}
  </div>
</div>

<input bind:this={fileInput} type="file" accept="audio/*" hidden onchange={onFileChosen} />

<style>
  .bottom {
    flex: none;
    border-top: 1px solid var(--divider);
    background: var(--bar);
    padding: 8px 16px 10px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .status {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    min-height: 28px;
    font-size: 0.85rem;
  }
  .phase {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .phase .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--secondary);
  }
  .phase.recording .dot {
    background: #ff3b30;
  }
  .phase.voice .dot {
    background: var(--voice);
  }
  .phase.reference .dot {
    background: var(--reference);
  }
  .time {
    color: var(--secondary);
    font-variant-numeric: tabular-nums;
  }
  .error {
    color: #ff3b30;
    font-size: 0.8rem;
  }
  .info {
    font-size: 0.85rem;
  }
  .info.record {
    color: var(--record);
    font-size: 0.8rem;
  }
  .rest,
  .warning {
    margin: 0;
    color: var(--warning);
    font-size: 0.8rem;
  }
  .buttons {
    display: flex;
    gap: 8px;
  }
  .icon {
    flex: none;
    width: 52px;
    padding: 14px 0;
    font-size: 1.05rem;
  }
  .action {
    flex: 1;
    padding: 14px 20px;
    font-size: 1.05rem;
    background: var(--target);
    color: #ffffff;
  }
  .stop {
    flex: 1;
    padding: 14px 20px;
    font-size: 1.05rem;
    background: color-mix(in srgb, #ff3b30 18%, transparent);
    color: #ff3b30;
  }
  .dev {
    flex: none;
    font-size: 0.75rem;
  }
</style>
