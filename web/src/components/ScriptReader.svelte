<script lang="ts">
  import {
    ANY_CATEGORY,
    estimatedSeconds,
    filterScripts,
    PRACTICE_SCRIPTS,
    SCRIPT_LENGTHS,
    scriptCategories,
    scriptDetails,
    type ScriptLength,
  } from '../data/scripts'
  import { PracticeDuration } from '../model/practice'
  import { settings } from '../model/settings.svelte'
  import { resolveParticles } from '../text/korean'

  /**
   * 대본 낭독 (iOS `ScriptReaderView`). 종류·길이로 거르고, 상자 안에서 스크롤해 읽고,
   * 들려줄 길이를 대본 길이에 맞출 수 있다. 그래프가 화면 위에 고정되어 있어서 대본은 이 상자 안에서 넘기며 읽는다.
   */
  let { isPracticing }: { isPracticing: boolean } = $props()

  const categories = scriptCategories()
  let index = $state(0)
  let textBox: HTMLDivElement | undefined = $state()

  const category = $derived(categories.includes(settings.scriptCategory) ? settings.scriptCategory : ANY_CATEGORY)
  const filtered = $derived(filterScripts(category, settings.scriptLength))
  const current = $derived(filtered[Math.min(index, filtered.length - 1)])
  const suggested = $derived(current ? PracticeDuration.suggestedFor(estimatedSeconds(current)) : null)

  // 대본이 바뀌면 스크롤을 맨 위로 되돌린다.
  $effect(() => {
    void current?.id
    textBox?.scrollTo({ top: 0 })
  })

  function chooseCategory(event: Event) {
    settings.setScriptCategory((event.target as HTMLSelectElement).value)
    index = 0
  }
  function chooseLength(event: Event) {
    settings.setScriptLength((event.target as HTMLSelectElement).value as ScriptLength)
    index = 0
  }
  function shuffle() {
    if (filtered.length < 2) return
    const others = filtered.map((_, i) => i).filter((i) => i !== index)
    index = others[Math.floor(Math.random() * others.length)]
  }
</script>

<div class="reader">
  <div class="filters">
    <select value={category} onchange={chooseCategory} aria-label="대본 종류">
      <option value={ANY_CATEGORY}>전체 종류</option>
      {#each categories as name (name)}
        <option value={name}>{name}</option>
      {/each}
    </select>
    <select value={settings.scriptLength} onchange={chooseLength} aria-label="대본 길이">
      {#each SCRIPT_LENGTHS as length (length.id)}
        <option value={length.id}>{length.label}</option>
      {/each}
    </select>
    <span class="spacer"></span>
    <button class="small" onclick={shuffle} disabled={filtered.length < 2} aria-label="다른 대본">⤨</button>
  </div>

  {#if current}
    <article class="card">
      <h3>{current.title}</h3>
      <p class="details">{scriptDetails(current)}</p>
      <!-- 스크롤되는 상자는 키보드로도 넘길 수 있게 초점을 받아야 한다 (WCAG: 스크롤 영역은 키보드로 닿아야 함). -->
      <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
      <div class="text" bind:this={textBox} tabindex="0" role="region" aria-label="대본 본문">
        <p>{current.text}</p>
      </div>
      {#if current.needsFactCheck}
        <p class="details">아직 사실 확인을 거치지 않은 글이에요.</p>
      {/if}
    </article>

    <nav class="navigation" aria-label="대본 넘기기">
      <button class="plain" onclick={() => (index = Math.max(0, index - 1))} disabled={index === 0}>‹ 이전</button>
      <span class="counter">{Math.min(index, filtered.length - 1) + 1} / {filtered.length}</span>
      <button class="plain" onclick={() => (index = Math.min(filtered.length - 1, index + 1))} disabled={index >= filtered.length - 1}>
        다음 ›
      </button>
    </nav>
    {#if suggested !== null}
      <button
        class="plain fit"
        onclick={() => settings.setPracticeDuration(suggested)}
        disabled={isPracticing || settings.practiceDuration === suggested}
      >
        ⏱ {resolveParticles(`들려줄 길이를 ${PracticeDuration.label(suggested)}(으)로 맞추기`)}
      </button>
    {/if}
  {:else}
    <p class="empty">{PRACTICE_SCRIPTS.length === 0 ? '대본 파일을 읽지 못했어요.' : '조건에 맞는 대본이 없어요.'}</p>
  {/if}
</div>

<style>
  .reader {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .filters {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }
  .spacer {
    flex: 1;
  }
  select {
    font: inherit;
    font-size: 0.85rem;
    color: var(--target);
    background: transparent;
    border: none;
    padding: 4px 0;
  }
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  h3 {
    margin: 0;
    font-size: 1.05rem;
  }
  .details {
    margin: 0;
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .text {
    height: 15rem;
    overflow-y: auto;
    overscroll-behavior: contain;
  }
  .text p {
    margin: 0;
    font-size: 1.05rem;
    line-height: 1.75;
    word-break: keep-all;
    overflow-wrap: break-word;
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
  .fit {
    align-self: center;
    font-size: 0.85rem;
  }
  .empty {
    color: var(--secondary);
    font-size: 0.85rem;
    min-height: 7.5rem;
    display: grid;
    place-items: center;
  }
</style>
