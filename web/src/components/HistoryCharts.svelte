<script lang="ts">
  import { formantTicks, position, ticks } from '../dsp/pitchScale'
  import type { Range } from '../dsp/range'
  import { dayCount, dayTicks, historyPlotRect, markerPath, minuteTicks, timeX, type DateDomain } from '../graph/historyChart'
  import type { DailyPractice, SessionPoint } from '../model/history'
  import { PRACTICE_LANGUAGES } from '../model/records'
  import { formatAxisDay } from '../text/dates'
  import LanguageTag from './LanguageTag.svelte'

  /**
   * [기록]의 그래프 세 개 (iOS `HistoryChartView`): 연습마다 목소리 높이(중앙값 점 + 아래 10%~위 10% 세로줄),
   * 연습마다 공명 밝기(F2 중앙값 점), 날마다 연습한 시간(막대).
   * 점은 목소리 색(분홍), 파란 띠는 지금 목표 범위, 보라 점선은 지금 기준(목소리 높이·F2), 막대는 기록 색(초록)이다 ([높이]와 같은 색).
   * 언어는 색이 아니라 점 모양으로 나눈다. 높이·F2 축은 반음 눈금이다. 좋아졌다·나빠졌다 같은 판정은 하지 않는다.
   */
  let {
    points,
    daily,
    domain,
    pitchDomain,
    target,
    baseline,
    resonanceDomain,
    baselineF2,
  }: {
    points: readonly SessionPoint[]
    daily: readonly DailyPractice[]
    domain: DateDomain
    pitchDomain: Range
    target: Range | null
    baseline: number | null
    /** [Hz] 공명 밝기 그래프의 세로축 */
    resonanceDomain: Range
    /** [Hz] 지금 기준 F2 (내 목소리 재기 때 저장). 없으면 점선을 그리지 않는다 */
    baselineF2: number | null
  } = $props()

  let width = $state(320)
  const pitchHeight = 220
  const resonanceHeight = 160
  const barHeight = 110

  const pitchPlot = $derived(historyPlotRect(width, pitchHeight))
  const barPlot = $derived(historyPlotRect(width, barHeight))
  const y = (frequency: number) => pitchPlot.y + pitchPlot.height - position(frequency, pitchDomain) * pitchPlot.height
  const resonancePlot = $derived(historyPlotRect(width, resonanceHeight))
  const resonanceY = (f2: number) =>
    resonancePlot.y + resonancePlot.height - position(f2, resonanceDomain) * resonancePlot.height
  const f2Ticks = $derived(formantTicks(resonanceDomain))
  /** F2 중앙값이 남은 연습만 (2026-10-25 전의 연습과 포먼트를 충분히 못 잡은 연습은 빠진다) */
  const resonancePoints = $derived(points.flatMap((point) => (point.f2 === null ? [] : [{ point, f2: point.f2 }])))
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
  const resonanceDescription = $derived.by(() => {
    if (resonancePoints.length === 0) return ''
    const values = resonancePoints.map((item) => Math.round(item.f2))
    return `연습 ${resonancePoints.length}번의 F2 중앙값이 ${Math.min(...values)}~${Math.max(...values)} Hz 사이에 있어요.${
      baselineF2 === null ? '' : ` 지금 기준은 ${Math.round(baselineF2)} Hz예요.`
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

  <!-- 공명 밝기(F2)는 내 기준과만 견준다. 성별 평균 같은 바깥 기준은 쓰지 않는다 (원칙 3).
       문장 속 F2는 말한 모음에 따라 달라지므로 같은 대본끼리 견줘야 한다는 안내를 빼지 않는다 ([높이] 공명 막대와 같은 안내). -->
  <div class="chart">
    <h3>연습마다 공명 밝기 (F2, Hz)</h3>
    {#if resonancePoints.length === 0}
      <p class="caption">
        이 기간의 연습에는 공명 밝기 기록이 없어요. 공명 밝기는 이 기능이 생긴 뒤의 연습부터 남고, 목소리의 공명이 충분히 잡히지 않은
        연습은 빠져요.
      </p>
    {:else}
      <svg
        width={width}
        height={resonanceHeight}
        role="img"
        aria-label="연습마다 공명 밝기"
        aria-describedby="resonance-chart-description"
      >
        {#each f2Ticks as hz (hz)}
          <line class="grid" x1={resonancePlot.x} x2={resonancePlot.x + resonancePlot.width} y1={resonanceY(hz)} y2={resonanceY(hz)} />
          <text class="label" x={resonancePlot.x - 6} y={resonanceY(hz)} text-anchor="end" dominant-baseline="middle">{hz}</text>
        {/each}
        {#each days as day (day.getTime())}
          <line
            class="grid"
            x1={timeX(day, domain, resonancePlot)}
            x2={timeX(day, domain, resonancePlot)}
            y1={resonancePlot.y}
            y2={resonancePlot.y + resonancePlot.height}
          />
          <text class="label" x={timeX(day, domain, resonancePlot)} y={resonanceHeight - 6} text-anchor="middle">{formatAxisDay(day)}</text>
        {/each}
        {#if baselineF2 !== null}
          <line
            class="baseline"
            x1={resonancePlot.x}
            x2={resonancePlot.x + resonancePlot.width}
            y1={resonanceY(baselineF2)}
            y2={resonanceY(baselineF2)}
          />
          <text class="baseline-label" x={resonancePlot.x + 4} y={resonanceY(baselineF2) - 4}>기준</text>
        {/if}
        {#each resonancePoints as item}
          <path class="point" d={markerPath(item.point.language, timeX(item.point.startedAt, domain, resonancePlot), resonanceY(item.f2), 3.8)} />
        {/each}
      </svg>
      <span id="resonance-chart-description" class="visually-hidden">{resonanceDescription}</span>
      <p class="caption">
        점은 연습 한 번의 F2 중앙값이에요. 위쪽이 밝은 쪽이고, 보라 점선은 지금 기준이에요. F2는 말한 모음에 따라 달라져서, 같은 대본을 읽은
        연습끼리 비교해야 정확해요.
      </p>
    {/if}
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
