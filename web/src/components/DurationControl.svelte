<script lang="ts">
  import { PracticeDuration } from '../model/practice'
  import { settings } from '../model/settings.svelte'

  /** ‘들려줄 길이’ 버튼과 작은 조정 창 (iOS `PracticeDurationView`). 그래프 가로축 길이이기도 하다. */
  let { locked }: { locked: boolean } = $props()

  let isEditing = $state(false)
  const label = $derived(PracticeDuration.label(settings.practiceDuration))
</script>

<div class="duration">
  <button class="plain small" onclick={() => (isEditing = !isEditing)} disabled={locked} aria-expanded={isEditing}>
    ⏱ 들려줄 길이 {label}
  </button>
  {#if isEditing && !locked}
    <div class="popover" role="dialog" aria-label="들려줄 길이">
      <div class="header"><span>들려줄 길이</span><span class="value">{label}</span></div>
      <div class="slider">
        <span>10초</span>
        <input
          type="range"
          min={PracticeDuration.range.lower}
          max={PracticeDuration.range.upper}
          step={PracticeDuration.step}
          value={settings.practiceDuration}
          oninput={(event) => settings.setPracticeDuration(Number((event.target as HTMLInputElement).value))}
          aria-label="들려줄 길이"
          aria-valuetext={label}
        />
        <span>3분</span>
      </div>
      <p class="note">그래프의 가로축도 이 길이예요.</p>
      <button class="plain small done" onclick={() => (isEditing = false)}>닫기</button>
    </div>
  {/if}
</div>

<style>
  .duration {
    position: relative;
  }
  .popover {
    position: absolute;
    right: 0;
    bottom: calc(100% + 8px);
    width: min(300px, calc(100vw - 32px));
    padding: 16px;
    border-radius: 14px;
    background: var(--background);
    box-shadow: 0 8px 30px rgb(0 0 0 / 0.25);
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 10;
  }
  .header {
    display: flex;
    justify-content: space-between;
    font-weight: 500;
  }
  .value {
    font-variant-numeric: tabular-nums;
  }
  .slider {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.8rem;
    color: var(--secondary);
  }
  .slider input {
    flex: 1;
    accent-color: var(--target);
  }
  .note {
    margin: 0;
    font-size: 0.75rem;
    color: var(--secondary);
  }
  .done {
    align-self: flex-end;
  }
</style>
