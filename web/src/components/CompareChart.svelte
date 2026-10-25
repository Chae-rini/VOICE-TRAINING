<script lang="ts">
  import { position, ticks } from '../dsp/pitchScale'
  import { PitchSummary } from '../dsp/pitchSummary'
  import type { Range } from '../dsp/range'
  import { historyPlotRect } from '../graph/historyChart'
  import { comparisonDomain, distribution, type ComparisonBin } from '../model/comparison'

  /**
   * 두 녹음의 높이 분포를 겹쳐 그린다 (iOS `RecordingCompareView.distributionChart`를 SVG로).
   * 가로축은 반음 눈금(Hz), 세로축은 목소리가 잡힌 시간 중 그 높이(반음 반 칸)에 머문 비율 [%].
   * A는 보라, B는 초록, 점선은 각 녹음의 중앙값, 파란 띠는 지금 목표 범위.
   */
  let { voicedA, voicedB, target }: { voicedA: readonly number[]; voicedB: readonly number[]; target: Range | null } = $props()

  let width = $state(320)
  const height = 200

  const domain = $derived(comparisonDomain(voicedA, voicedB, target))
  const binsA = $derived(distribution(voicedA, domain))
  const binsB = $derived(distribution(voicedB, domain))
  const yMax = $derived(Math.max(Math.max(0, ...binsA.map((b) => b.fraction), ...binsB.map((b) => b.fraction)) * 100 * 1.15, 10))
  const yStep = $derived([5, 10, 20, 25, 50].find((step) => yMax / step <= 4) ?? 50)
  const yTicks = $derived(Array.from({ length: Math.floor(yMax / yStep) + 1 }, (_, i) => i * yStep))
  const plot = $derived(historyPlotRect(width, height))
  const x = (frequency: number) => plot.x + Math.min(Math.max(position(frequency, domain), 0), 1) * plot.width
  const y = (percent: number) => plot.y + plot.height - (percent / yMax) * plot.height
  const medianOf = (voiced: readonly number[]) => PitchSummary.percentile([...voiced].sort((a, b) => a - b), 0.5)

  function linePath(bins: readonly ComparisonBin[]): string {
    return bins.map((bin, i) => `${i === 0 ? 'M' : 'L'} ${x(bin.center)} ${y(bin.fraction * 100)}`).join(' ')
  }

  function areaPath(bins: readonly ComparisonBin[]): string {
    if (bins.length === 0) return ''
    const bottom = y(0)
    return `M ${x(bins[0].center)} ${bottom} ${bins.map((bin) => `L ${x(bin.center)} ${y(bin.fraction * 100)}`).join(' ')} L ${x(bins[bins.length - 1].center)} ${bottom} Z`
  }

  const description = $derived(
    `A의 중앙값 ${Math.round(medianOf(voicedA))} Hz, B의 중앙값 ${Math.round(medianOf(voicedB))} Hz. 가로축 ${Math.round(domain.lower)}~${Math.round(domain.upper)} Hz.`,
  )
</script>

<div class="chart" bind:clientWidth={width}>
  <svg {width} {height} role="img" aria-label="두 녹음의 높이 분포" aria-describedby="compare-chart-description">
    {#if target !== null}
      <rect class="band" x={x(target.lower)} y={plot.y} width={Math.max(x(target.upper) - x(target.lower), 0)} height={plot.height} />
    {/if}
    {#each yTicks as tick (tick)}
      <line class="grid" x1={plot.x} x2={plot.x + plot.width} y1={y(tick)} y2={y(tick)} />
      <text class="label" x={plot.x - 6} y={y(tick)} text-anchor="end" dominant-baseline="middle">{tick}%</text>
    {/each}
    {#each ticks(domain) as hz (hz)}
      <line class="grid" x1={x(hz)} x2={x(hz)} y1={plot.y} y2={plot.y + plot.height} />
      <text class="label" x={x(hz)} y={height - 6} text-anchor="middle">{hz}</text>
    {/each}
    <text class="label" x={plot.x + plot.width} y={height - 6} text-anchor="end">Hz</text>

    <path class="area a" d={areaPath(binsA)} />
    <path class="area b" d={areaPath(binsB)} />
    <path class="line a" d={linePath(binsA)} />
    <path class="line b" d={linePath(binsB)} />
    {#if voicedA.length > 0}
      <line class="median a" x1={x(medianOf(voicedA))} x2={x(medianOf(voicedA))} y1={plot.y} y2={plot.y + plot.height} />
    {/if}
    {#if voicedB.length > 0}
      <line class="median b" x1={x(medianOf(voicedB))} x2={x(medianOf(voicedB))} y1={plot.y} y2={plot.y + plot.height} />
    {/if}
  </svg>
  <span id="compare-chart-description" class="visually-hidden">{description}</span>
</div>

<style>
  svg {
    display: block;
    overflow: visible;
  }
  .grid {
    stroke: var(--secondary);
    stroke-opacity: 0.2;
    stroke-width: 0.5;
  }
  .label {
    fill: var(--secondary);
    font-size: 10px;
    font-variant-numeric: tabular-nums;
  }
  .band {
    fill: var(--target);
    opacity: 0.18;
  }
  .area {
    opacity: 0.15;
  }
  .area.a {
    fill: var(--reference);
  }
  .area.b {
    fill: var(--record);
  }
  .line {
    fill: none;
    stroke-width: 2;
    stroke-linejoin: round;
  }
  .line.a,
  .median.a {
    stroke: var(--reference);
  }
  .line.b,
  .median.b {
    stroke: var(--record);
  }
  .median {
    stroke-width: 1.5;
    stroke-dasharray: 4 3;
  }
</style>
