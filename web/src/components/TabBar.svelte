<script lang="ts">
  import { navigation, type AppTab } from './navigation.svelte'

  /** 아래 탭 막대: [높이] [모음] [기록]. 지금 탭은 강조색과 굵은 글자로 (색에만 기대지 않게). */
  const tabs: { id: AppTab; label: string }[] = [
    { id: 'pitch', label: '높이' },
    { id: 'vowel', label: '모음' },
    { id: 'history', label: '기록' },
  ]
</script>

<nav class="tabs" aria-label="화면">
  {#each tabs as tab (tab.id)}
    <button
      class="tab"
      class:current={navigation.tab === tab.id}
      aria-current={navigation.tab === tab.id ? 'page' : undefined}
      onclick={() => (navigation.tab = tab.id)}
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        {#if tab.id === 'pitch'}
          <!-- 높낮이 곡선 -->
          <path d="M2 14 Q5 6 8 12 T14 10 T22 8" />
        {:else if tab.id === 'vowel'}
          <!-- 입 모양 -->
          <path d="M3 12 Q12 3 21 12 Q12 21 3 12 Z" />
          <path d="M3 12 H21" />
        {:else}
          <!-- 달력 -->
          <rect x="3.5" y="5" width="17" height="15" rx="2.5" />
          <path d="M3.5 10 H20.5 M8 3 V7 M16 3 V7" />
        {/if}
      </svg>
      <span>{tab.label}</span>
    </button>
  {/each}
</nav>

<style>
  .tabs {
    flex: none;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    border-top: 1px solid var(--divider);
    background: var(--bar);
    padding: 4px 8px env(safe-area-inset-bottom);
  }
  .tab {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 6px 0 8px;
    border-radius: 10px;
    background: none;
    color: var(--secondary);
    font-size: 0.7rem;
  }
  .tab.current {
    color: var(--target);
    font-weight: 600;
  }
  svg {
    width: 24px;
    height: 24px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  .tab.current svg {
    stroke-width: 2.4;
  }
</style>
