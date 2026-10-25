<script lang="ts">
  import { position, ticks } from '../dsp/pitchScale'
  import type { Range } from '../dsp/range'
  import { dayCount, dayTicks, historyPlotRect, markerPath, minuteTicks, timeX, type DateDomain } from '../graph/historyChart'
  import type { DailyPractice, SessionPoint } from '../model/history'
  import { PRACTICE_LANGUAGES } from '../model/records'
  import { formatAxisDay } from '../text/dates'
  import LanguageTag from './LanguageTag.svelte'

  /**
   * [기록]의 그래프 두 개 (iOS `HistoryChartView`): 연습마다 목소리 높이(중앙값 점 + 아래 10%~위 10% 세로줄), 날마다 연습한 시간(막대).
   * 점은 목소리 색(분홍), 파란 띠는 지금 목표 범위, 보라 점선은 지금 기준 목소리, 막대는 기록 색(초록)이다 ([높이]와 같은 색).
   * 언어는 색이 아니라 점 모양으로 나눈다. 높이 축은 반음 눈금이다. 좋아졌다·나빠졌다 같은 판정은 하지 않는다.
   */
  let {
    points,
    daily,
    domain,
    pitchDomain,
    target,
    baseline,
  }: {
    points: readonly SessionPoint[]
    daily: readonly DailyPractice[]
    domain: DateDomain
    pitchDomain: Range
    target: Range | null
    baseline: number | null
  } = $props()

  let width = $state(320)
  const pitchHeight = 220
  const barHeight = 110

  const pitchPlot = $derived(historyPlotRect(width, pitchHeight))
  const barPlot = $derived(historyPlotRect(width, barHeight))
  const y = (frequency: number) => pitchPlot.y + pitchPlot.height - position(frequency, pitchDomain) * pitchPlot.height
  const dayWidth = $derived(barPlot.width / dayCount(domain))
  const days = $derived(dayTicks(domain))
  const hzTicks = $derived(ticks(pitchDomain))
  const maxMinutes = $derived(Math.max(...daily.map((d) => d.minutes), 1))
  const minuteMarks = $derived(minuteTicks(maxMinutes))
  const minuteTop = $derived(minuteMarks[minuteMarks.length - 1])
  const barY = (minutes: number) => barPlot.y + barPlot.height - (minutes / minuteTop) * barPlot.height
  /** 그래프에 나온 언어만 범례에 넣는다 */
  const languages = $derived(PRACTICE_LANGUAGES.filter((l) => points.some((p) => p.language === l.id)).map((l) => l.id))

  const pitchDescription = $derived.by(() => {
    if (points.length === 0) return ''
    const medians = points.map((p) => Math.round(p.median))
    return `연습 ${points.length}번의 중앙값이 ${Math.min(...medians)}~${Math.max(...medians)} Hz 사이에 있어요.${
      target === null ? '' : ` 지금 목표 범위는 ${Math.round(target.lower)}~${Math.round(target.upper)} Hz예요.`
    }`
  })
  const barDescription = $derived(
    `연습한 날 ${daily.length}일, 가장 오래 연습한 날은 ${Math.round(maxMinutes)}분이에요.`,
  )
</script>

<div class="charts" bind:clientWidth={width}>
  <div class="chart">
    <h3>연습마다 목소리 높이 (Hz)</h3>
    <svg width={width} height={pitchHeight} role="img" aria-label="연습마다 목소리 높이" aria-describedby="pitch-chart-description">
      {#if target !== null}
        <rect
          class="band"
          x={pitchPlot.x}
          y={y(target.upper)}
          width={pitchPlot.width}
          height={Math.max(y(target.lower) - y(target.upper), 0)}
        />
      {/if}
      {#each hzTicks as hz (hz)}
        <line class="grid" x1={pitchPlot.x} x2={pitchPlot.x + pitchPlot.width} y1={y(hz)} y2={y(hz)} />
        <text class="label" x={pitchPlot.x - 6} y={y(hz)} text-anchor="end" dominant-baseline="middle">{hz}</text>
      {/each}
      {#each days as day (day.getTime())}
        <line class="grid" x1={timeX(day, domain, pitchPlot)} x2={timeX(day, domain, pitchPlot)} y1={pitchPlot.y} y2={pitchPlot.y + pitchPlot.height} />
        <text class="label" x={timeX(day, domain, pitchPlot)} y={pitchHeight - 6} text-anchor="middle">{formatAxisDay(day)}</text>
      {/each}
      {#if baseline !== null}
        <line class="baseline" x1={pitchPlot.x} x2={pitchPlot.x + pitchPlot.width} y1={y(baseline)} y2={y(baseline)} />
        <text class="baseline-label" x={pitchPlot.x + 4} y={y(baseline) - 4}>기준</text>
      {/if}
      {#each points as point}
        {@const x = timeX(point.startedAt, domain, pitchPlot)}
        <line class="range" x1={x} x2={x} y1={y(point.low)} y2={y(point.high)} />
        <path class="point" d={markerPath(point.language, x, y(point.median), 3.8)} />
      {/each}
    </svg>
    <span id="pitch-chart-description" class="visually-hidden">{pitchDescription}</span>
    {#if languages.length > 1}
      <div class="legend">
        {#each languages as language (language)}<LanguageTag {language} plain />{/each}
      </div>
    {/if}
    <p class="caption">
      점은 연습 한 번의 중앙값, 세로줄은 아래 10%~위 10%예요. 파란 띠는 지금 목표 범위, 보라 점선은 지금 기준 목소리예요.
    </p>
  </div>

  <div class="chart">
    <h3>날마다 연습한 시간 (분)</h3>
    <svg width={width} height={barHeight} role="img" aria-label="날마다 연습한 시간" aria-describedby="bar-chart-description">
      {#each minuteMarks as minutes (minutes)}
        <line class="grid" x1={barPlot.x} x2={barPlot.x + barPlot.width} y1={barY(minutes)} y2={barY(minutes)} />
        <text class="label" x={barPlot.x - 6} y={barY(minutes)} text-anchor="end" dominant-baseline="middle">{minutes}</text>
      {/each}
      {#each days as day (day.getTime())}
        <text class="label" x={timeX(day, domain, barPlot)} y={barHeight - 6} text-anchor="middle">{formatAxisDay(day)}</text>
      {/each}
      {#each daily as day (day.day.getTime())}
        {@const barWidth = Math.max(2, dayWidth * 0.6)}
        <rect
          class="bar"
          x={timeX(day.day, domain, barPlot) + (dayWidth - barWidth) / 2}
          y={barY(day.minutes)}
          width={barWidth}
          height={barPlot.y + barPlot.height - barY(day.minutes)}
          rx="1.5"
        />
      {/each}
    </svg>
    <span id="bar-chart-description" class="visually-hidden">{barDescription}</span>
  </div>
</div>

<style>
  .charts {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .chart {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  h3 {
    margin: 0;
    font-size: 0.85rem;
  }
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
  .baseline {
    stroke: var(--reference);
    stroke-width: 1.5;
    stroke-dasharray: 5 4;
  }
  .baseline-label {
    fill: var(--reference);
    font-size: 10px;
  }
  .range {
    stroke: var(--voice);
    stroke-opacity: 0.35;
    stroke-width: 2;
    stroke-linecap: round;
  }
  .point {
    fill: var(--voice);
  }
  .bar {
    fill: var(--record);
    opacity: 0.8;
  }
  .legend {
    display: flex;
    gap: 12px;
  }
  .caption {
    margin: 0;
    color: var(--secondary);
    font-size: 0.75rem;
  }
</style>
