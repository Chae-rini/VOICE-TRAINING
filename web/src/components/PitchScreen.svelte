<script lang="ts">
  import { onMount } from 'svelte'
  import { processingNotice } from '../audio/processing'
  import { GraphWindow } from '../dsp/graphWindow'
  import { graphHeight } from '../graph/pitchGraph'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'
  import { takeSummary } from '../practice/take'
  import BaselineSheet from './BaselineSheet.svelte'
  import DurationControl from './DurationControl.svelte'
  import LivePanel from './LivePanel.svelte'
  import SentenceCards from './SentenceCards.svelte'
  import SummaryCard from './SummaryCard.svelte'
  import TargetRangeControls from './TargetRangeControls.svelte'

  /**
   * [높이] 화면 (iOS `ContentView.practiceScreen` + `PracticeControlsView`): 높이 숫자와 그래프는 위에 고정하고,
   * 그 아래(목표 범위·요약 카드·문장·대본)만 스크롤한다. 단계별 버튼은 늘 화면 아래에 보인다.
   * - 쉬는 중: [녹음 불러오기] [▶ 마지막 녹음] [반복 루프 재생] → 정지할 때까지 녹음이 이어진다
   * - 녹음 중: [정지] [지금 들어보기] → 최근 녹음을 들려주고, 끝나면 자동으로 다시 녹음
   * - 듣는 중: [정지] [건너뛰기]
   */
  const isDev = import.meta.env.DEV
  let available = $state(600)
  let sheetOpen = $state(false)
  let fileInput: HTMLInputElement

  /** 대본을 읽는 중이면 그래프를 줄여(읽기 모드) 대본 자리를 넓힌다 */
  const compact = $derived(settings.sentenceSource === 'scripts')
  const height = $derived(graphHeight(available, compact))
  const phase = $derived(session.phase)
  const notice = $derived(phase.kind === 'recording' ? processingNotice(session.processing) : null)
  /** 마지막 녹음의 요약. 녹음하는 동안에는 숨긴다 */
  const summary = $derived(
    session.lastTake === null || phase.kind === 'recording' ? null : takeSummary(session.lastTake, settings.target),
  )

  const caption = $derived.by(() => {
    if (session.busy === 'starting') return '마이크를 켜는 중…'
    switch (phase.kind) {
      case 'recording':
        return '현재 목소리 높이'
      case 'listening':
      case 'replaying':
        return '녹음을 다시 듣는 중'
      case 'countdown':
        return '곧 다시 녹음해요'
      case 'measuring':
        return '내 목소리 재는 중'
      case 'idle':
        return session.lastTake !== null ? '마지막 녹음' : '‘반복 루프 재생’을 누르면 녹음과 분석을 시작해요'
    }
  })

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
        return { text: '내 목소리 재는 중', time: GraphWindow.timeLabel(session.remaining), tone: 'reference' }
      case 'idle':
        return null
    }
  })

  onMount(() => {
    // 처음 열 때 한 번: 기준 목소리를 아직 안 쟀으면 재기 화면을 띄운다 ("나중에"로 건너뛸 수 있음).
    if (settings.baseline === null && !settings.baselinePromptShown) {
      settings.markBaselinePromptShown()
      sheetOpen = true
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

<div class="screen">
  <div class="main" bind:clientHeight={available}>
    <div class="top">
      <LivePanel {compact} {height} {caption} />
    </div>

    <div class="scroll">
      {#if settings.isTemporary}
        <p class="banner">이 브라우저가 저장을 막고 있어서, 목표 범위와 기준은 이 페이지를 닫기 전까지만 기억돼요.</p>
      {/if}
      <TargetRangeControls canMeasure={!session.isRunning} onMeasure={() => (sheetOpen = true)} />
      {#if session.lastTake !== null && summary !== null}
        <SummaryCard take={session.lastTake} {summary} />
      {/if}
      <SentenceCards isPracticing={session.isRunning} />
      <div class="guide">
        <p>
          음량은 이 기기 마이크가 받은 소리 크기(dBFS, 0이 마이크가 받을 수 있는 최대)예요. 마이크마다 값이 달라서 귀로 듣는
          절대 데시벨(dB SPL)이 아니에요.
        </p>
        <p>
          공명 밝기는 최근 2.5초 목소리의 둘째 포먼트(F2) 중앙값이에요. 가운데 보라 선은 내 목소리 재기 때의 값이에요. 문장 속
          공명은 어떤 모음을 말했는지에 따라 달라져요. 같은 대본을 읽을 때 비교하면 정확해요. 점이 비어 있으면 목소리가 높아 값이
          불확실할 수 있어요.
        </p>
        <p>소리는 이 기기 안에서만 분석하고 어디로도 보내지 않아요. 울림은 의료 기기가 아니에요.</p>
      </div>
    </div>
  </div>

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
        {:else if session.errorMessage !== null && !sheetOpen}
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
</div>

<input bind:this={fileInput} type="file" accept="audio/*" hidden onchange={onFileChosen} />
<BaselineSheet open={sheetOpen} onClose={() => (sheetOpen = false)} />

<style>
  .screen {
    height: 100dvh;
    max-width: 560px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
  }
  .main {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .top {
    flex: none;
    padding: max(8px, env(safe-area-inset-top)) 16px 10px;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    border-top: 1px solid var(--divider);
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .banner {
    margin: 0;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--card);
    color: var(--warning);
    font-size: 0.85rem;
  }
  .guide {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .guide p {
    margin: 0 0 4px;
  }
  .bottom {
    flex: none;
    border-top: 1px solid var(--divider);
    background: var(--bar);
    padding: 8px 16px calc(10px + env(safe-area-inset-bottom));
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
