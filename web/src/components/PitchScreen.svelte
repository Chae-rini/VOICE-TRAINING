<script lang="ts">
  import { onMount } from 'svelte'
  import { graphHeight } from '../graph/pitchGraph'
  import { PRACTICE_LANGUAGES, type PracticeLanguage } from '../model/records'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'
  import { takeSummary } from '../practice/take'
  import BaselineSheet from './BaselineSheet.svelte'
  import LivePanel from './LivePanel.svelte'
  import { navigation } from './navigation.svelte'
  import SentenceCards from './SentenceCards.svelte'
  import StorageNotice from './StorageNotice.svelte'
  import SummaryCard from './SummaryCard.svelte'
  import TargetRangeControls from './TargetRangeControls.svelte'

  /**
   * [높이] 화면 (iOS `ContentView.practiceScreen`): 높이 숫자와 그래프는 위에 고정하고,
   * 그 아래(목표 범위·요약 카드·문장·대본)만 스크롤한다. 녹음·듣기 버튼은 [모음] 화면과 함께 쓰는 `PracticeControls`에 있다.
   */
  let available = $state(600)

  /** 대본을 읽는 중이면 그래프를 줄여(읽기 모드) 대본 자리를 넓힌다 */
  const compact = $derived(settings.sentenceSource === 'scripts')
  const height = $derived(graphHeight(available, compact))
  const phase = $derived(session.phase)
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
        return session.measuringVowel !== null ? `‘${session.measuringVowel}’ 길게 내는 중` : '내 목소리 재는 중'
      case 'idle':
        return session.lastTake !== null ? '마지막 녹음' : '‘반복 루프 재생’을 누르면 녹음과 분석을 시작해요'
    }
  })

  onMount(() => {
    // 처음 열 때 한 번: 기준 목소리를 아직 안 쟀으면 재기 화면을 띄운다 ("나중에"로 건너뛸 수 있음).
    if (settings.baseline === null && !settings.baselinePromptShown) {
      settings.markBaselinePromptShown()
      navigation.baselineSheetOpen = true
    }
  })
</script>

<div class="screen">
  <div class="main" bind:clientHeight={available}>
    <div class="top">
      <LivePanel {compact} {height} {caption} />
    </div>

    <div class="scroll">
      <StorageNotice />
      <TargetRangeControls canMeasure={!session.isRunning} onMeasure={() => (navigation.baselineSheetOpen = true)} />
      {#if session.lastTake !== null && summary !== null}
        <SummaryCard take={session.lastTake} {summary} />
      {/if}
      <SentenceCards isPracticing={session.isRunning} />
      <!-- 말하는 언어는 문장 아래에 둔다. 기록에 함께 남아 나중에 언어별로 높이를 비교한다. 연습 중에는 바꾸지 않는다 -->
      <label class="language">
        <span>🌐 말하는 언어</span>
        <select
          value={settings.practiceLanguage}
          onchange={(event) => settings.setPracticeLanguage((event.currentTarget as HTMLSelectElement).value as PracticeLanguage)}
          disabled={session.isRunning}
        >
          {#each PRACTICE_LANGUAGES as language (language.id)}
            <option value={language.id}>{language.label}</option>
          {/each}
        </select>
      </label>
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
</div>

<BaselineSheet open={navigation.baselineSheetOpen} onClose={() => (navigation.baselineSheetOpen = false)} />

<style>
  .screen {
    height: 100%;
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
  .language {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 4px;
    font-size: 0.9rem;
  }
  .language select {
    font: inherit;
    color: var(--target);
    background: var(--fill);
    border: none;
    border-radius: 8px;
    padding: 6px 10px;
  }
  .guide {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .guide p {
    margin: 0 0 4px;
  }
</style>
