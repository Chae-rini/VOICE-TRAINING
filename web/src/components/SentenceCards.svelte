<script lang="ts">
  import { PRACTICE_SENTENCES } from '../data/sentences'
  import { settings } from '../model/settings.svelte'
  import { SENTENCE_SOURCES } from '../model/settingsStorage'
  import { vowelSummary } from '../text/korean'
  import { SentenceGenerator } from '../text/sentenceGenerator'
  import ScriptReader from './ScriptReader.svelte'

  /**
   * 한국어 연습 문장 카드 (iOS `SentenceCardView`). 좌우로 밀거나 이전/다음 버튼으로 넘긴다.
   * 직접 쓴 문장, 패턴으로 자동 생성한 문장, 긴 낭독 대본 중에서 고를 수 있다.
   */
  let { isPracticing }: { isPracticing: boolean } = $props()

  const generator = new SentenceGenerator()
  let generated: string[] = $state(generator.makeDeck().map((sentence) => sentence.text))
  let index = $state(0)

  const sentences = $derived(settings.sentenceSource === 'mine' ? PRACTICE_SENTENCES : generated)
  const current = $derived(sentences[Math.min(index, sentences.length - 1)] ?? '')

  function choose(source: (typeof SENTENCE_SOURCES)[number]['id']) {
    settings.setSentenceSource(source)
    index = 0
  }

  function regenerate() {
    generated = generator.makeDeck().map((sentence) => sentence.text)
    index = 0
  }

  // 좌우로 밀어 넘기기
  let swipeStartX: number | null = null
  function onPointerDown(event: PointerEvent) {
    swipeStartX = event.clientX
  }
  function onPointerUp(event: PointerEvent) {
    if (swipeStartX === null) return
    const dx = event.clientX - swipeStartX
    swipeStartX = null
    if (dx < -40 && index < sentences.length - 1) index += 1
    else if (dx > 40 && index > 0) index -= 1
  }
</script>

<section class="sentences" aria-label="연습 문장">
  <div class="source-row">
    <div class="segmented" role="radiogroup" aria-label="문장 종류">
      {#each SENTENCE_SOURCES as source (source.id)}
        <button
          role="radio"
          aria-checked={settings.sentenceSource === source.id}
          class:selected={settings.sentenceSource === source.id}
          onclick={() => choose(source.id)}
        >
          {source.label}
        </button>
      {/each}
    </div>
    {#if settings.sentenceSource === 'generated'}
      <button class="small" onclick={regenerate}>⟳ 새 문장</button>
    {/if}
  </div>

  {#if settings.sentenceSource === 'scripts'}
    <ScriptReader {isPracticing} />
  {:else}
    <div
      class="card"
      onpointerdown={onPointerDown}
      onpointerup={onPointerUp}
      onpointercancel={() => (swipeStartX = null)}
      role="group"
      aria-roledescription="문장 카드"
      aria-label={`${index + 1} / ${sentences.length}`}
    >
      <p class="sentence">{current}</p>
      <p class="vowels">{vowelSummary(current)}</p>
    </div>
    <nav class="navigation" aria-label="문장 넘기기">
      <button class="plain" onclick={() => (index -= 1)} disabled={index === 0}>‹ 이전</button>
      <span class="counter">{index + 1} / {sentences.length}</span>
      <button class="plain" onclick={() => (index += 1)} disabled={index >= sentences.length - 1}>다음 ›</button>
    </nav>
  {/if}
</section>

<style>
  .sentences {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .source-row {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .segmented {
    flex: 1;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    background: var(--fill);
    border-radius: 9px;
    padding: 2px;
  }
  .segmented button {
    border-radius: 7px;
    padding: 6px 4px;
    background: transparent;
    color: var(--text);
    font-size: 0.85rem;
  }
  .segmented button.selected {
    background: var(--background);
    box-shadow: 0 1px 3px rgb(0 0 0 / 0.15);
    font-weight: 500;
  }
  .card {
    min-height: 7.5rem;
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    text-align: center;
    touch-action: pan-y;
    user-select: none;
  }
  .sentence {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 500;
    word-break: keep-all;
    overflow-wrap: break-word;
  }
  .vowels {
    margin: 0;
    color: var(--secondary);
    font-size: 0.75rem;
    white-space: pre;
  }
  .navigation {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 0.9rem;
  }
  .counter {
    color: var(--secondary);
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }
</style>
