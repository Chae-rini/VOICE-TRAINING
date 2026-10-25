<script lang="ts">
  import { FREQUENCY_RANGE } from '../dsp/pitchDetector'
  import { frequencyAtPosition, position, semitones } from '../dsp/pitchScale'
  import { Baseline, TargetRange } from '../model/practice'
  import { settings } from '../model/settings.svelte'

  /**
   * 목표 범위 한 줄(접기·펼치기)과 슬라이더, 내 목소리 재기 버튼 (iOS `TargetRangeControls`).
   * 슬라이더는 그래프와 같은 반음 눈금이라, 같은 거리만큼 끌면 어느 높이에서든 같은 반음만큼 움직인다.
   */
  let { canMeasure, onMeasure }: { canMeasure: boolean; onMeasure: () => void } = $props()

  let isAdjusting = $state(false)
  const target = $derived(settings.target)
  const baseline = $derived(settings.baseline)

  /** 슬라이더는 0~1000 위치를 다루고, 저장·표시는 Hz로 한다 */
  const SCALE = 1000
  const toSlider = (frequency: number) => Math.round(position(frequency, FREQUENCY_RANGE) * SCALE)
  const fromSlider = (value: number) => frequencyAtPosition(value / SCALE, FREQUENCY_RANGE)

  function setLower(event: Event) {
    if (target === null) return
    settings.setTarget(TargetRange.withLower(target, fromSlider(Number((event.target as HTMLInputElement).value))))
  }
  function setUpper(event: Event) {
    if (target === null) return
    settings.setTarget(TargetRange.withUpper(target, fromSlider(Number((event.target as HTMLInputElement).value))))
  }
</script>

<section class="target" aria-label="목표 범위">
  <div class="header">
    <span class="title">목표 범위</span>
    {#if target !== null}
      <span class="value">{TargetRange.label(target)}</span>
      <button
        class="small"
        onclick={() => (isAdjusting = !isAdjusting)}
        aria-expanded={isAdjusting}
        aria-label={isAdjusting ? '목표 범위 슬라이더 접기' : '목표 범위 슬라이더 펼치기'}
      >
        {isAdjusting ? '▴' : '▾'} 조정
      </button>
    {/if}
  </div>

  <!-- 기준에서 많이 떨어진 목표: 막거나 권하지 않고, 목 상태만 확인하도록 부드럽게 알린다 (접혀 있어도 보인다). -->
  {#if target !== null && baseline !== null && Baseline.isFar(target, baseline.median)}
    <p class="note">ⓘ 기준 목소리와 꽤 떨어진 범위예요. 목에 무리가 없는지 천천히 확인해 보세요.</p>
  {/if}

  {#if target === null}
    <p class="note">아직 목표 범위가 없어요. 내 목소리를 먼저 재면 그 높이를 기준으로 목표 범위를 만들어요.</p>
    <button class="measure" onclick={onMeasure} disabled={!canMeasure}>
      {baseline === null ? '내 목소리 재기' : `내 목소리 다시 재기 · 기준 ${Math.round(baseline.median)} Hz`}
    </button>
  {:else if isAdjusting}
    <label class="slider">
      <span>하한</span>
      <input
        type="range"
        min="0"
        max={SCALE}
        value={toSlider(target.lower)}
        oninput={setLower}
        aria-label="목표 하한"
        aria-valuetext={`${Math.trunc(target.lower)} Hz`}
      />
    </label>
    <label class="slider">
      <span>상한</span>
      <input
        type="range"
        min="0"
        max={SCALE}
        value={toSlider(target.upper)}
        oninput={setUpper}
        aria-label="목표 상한"
        aria-valuetext={`${Math.trunc(target.upper)} Hz`}
      />
    </label>
    <!-- 폭을 반음으로도 알려 준다: 같은 Hz 폭이라도 낮은 쪽이 귀로는 더 넓다. -->
    <p class="note">목표 범위의 폭은 반음 {semitones(target.lower, target.upper).toFixed(1)}개예요.</p>
    <p class="note">편하게 낼 수 있는 높이로 정하세요. 목이 불편하면 잠시 쉬어 가요.</p>
    <button class="measure" onclick={onMeasure} disabled={!canMeasure}>
      {baseline === null ? '내 목소리 재기' : `내 목소리 다시 재기 · 기준 ${Math.round(baseline.median)} Hz`}
    </button>
  {/if}
</section>

<style>
  .target {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .header {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    font-weight: 500;
  }
  .title {
    flex: 1;
  }
  .value {
    color: var(--target);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .note {
    margin: 0;
    color: var(--secondary);
    font-size: 0.8rem;
  }
  .slider {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.85rem;
  }
  .slider span {
    width: 32px;
    flex: none;
  }
  .slider input {
    flex: 1;
    accent-color: var(--target);
  }
  .measure {
    align-self: flex-start;
    color: var(--reference);
  }
</style>
