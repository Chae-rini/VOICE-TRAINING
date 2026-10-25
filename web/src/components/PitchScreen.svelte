<script lang="ts">
  import { onMount } from 'svelte'
  import { processingNotice } from '../audio/processing'
  import { GraphWindow } from '../dsp/graphWindow'
  import { graphHeight } from '../graph/pitchGraph'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'
  import BaselineSheet from './BaselineSheet.svelte'
  import DurationControl from './DurationControl.svelte'
  import LivePanel from './LivePanel.svelte'
  import SentenceCards from './SentenceCards.svelte'
  import TargetRangeControls from './TargetRangeControls.svelte'

  /**
   * [높이] 화면 (iOS `ContentView.practiceScreen`): 높이 숫자와 그래프는 위에 고정하고,
   * 그 아래(목표 범위·문장·대본)만 스크롤한다. 시작 버튼은 늘 화면 아래에 보인다.
   * W3에서는 마이크를 켠 동안 그래프가 흐른다 (녹음 → 듣기 반복은 W4).
   */
  const isDev = import.meta.env.DEV
  let available = $state(600)
  let sheetOpen = $state(false)

  /** 대본을 읽는 중이면 그래프를 줄여(읽기 모드) 대본 자리를 넓힌다 */
  const compact = $derived(settings.sentenceSource === 'scripts')
  const height = $derived(graphHeight(available, compact))
  const notice = $derived(session.phase === 'live' ? processingNotice(session.processing) : null)

  const caption = $derived.by(() => {
    switch (session.phase) {
      case 'live':
        return '현재 목소리 높이'
      case 'starting':
        return '마이크를 켜는 중…'
      case 'measuring':
        return '내 목소리 재는 중'
      case 'idle':
        return session.clock.kind === 'frozen' && session.clock.window !== null
          ? '마이크를 끈 때의 모습'
          : '‘마이크 켜기’를 누르면 목소리 높이를 그려요'
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
    void session.startLive(testTone ? { kind: 'testTone', testToneHz: 180 } : { kind: 'mic' }, settings.practiceDuration)
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
      {#if session.phase === 'live'}
        <span class="live"><span class="dot" aria-hidden="true"></span>마이크 켜짐 · {GraphWindow.timeLabel(session.elapsed)}</span>
      {:else if session.errorMessage !== null && !sheetOpen}
        <span class="error" role="alert">{session.errorMessage}</span>
      {:else}
        <span></span>
      {/if}
      <DurationControl locked={session.isRunning} />
    </div>
    {#if notice !== null}
      <p class="warning">{notice}</p>
    {/if}
    <div class="buttons">
      {#if session.phase === 'live'}
        <button class="action stop" onclick={() => session.stopLive()}>■ 정지</button>
      {:else}
        <button class="action" onclick={() => start()} disabled={session.phase !== 'idle'}>
          {session.phase === 'starting' ? '켜는 중…' : '🎙 마이크 켜기'}
        </button>
        {#if isDev}
          <button class="dev" onclick={() => start(true)} disabled={session.phase !== 'idle'}>테스트 음 (개발용)</button>
        {/if}
      {/if}
    </div>
  </div>
</div>

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
  .live {
    display: flex;
    align-items: center;
    gap: 6px;
    font-variant-numeric: tabular-nums;
  }
  .live .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #ff3b30;
  }
  .error {
    color: #ff3b30;
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
  .action {
    flex: 1;
    padding: 14px 20px;
    font-size: 1.05rem;
    background: var(--target);
    color: #ffffff;
  }
  .action.stop {
    background: color-mix(in srgb, #ff3b30 18%, transparent);
    color: #ff3b30;
  }
  .dev {
    font-size: 0.8rem;
  }
</style>
