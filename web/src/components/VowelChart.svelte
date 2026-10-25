<script lang="ts">
  import { onMount } from 'svelte'
  import { clockEndTime, clockIsMoving } from '../dsp/pitchHistory'
  import { VowelSpace, type VowelPoint } from '../dsp/vowelSpace'
  import type { GraphColors } from '../graph/pitchGraph'
  import {
    CHART_HEIGHT,
    comparisonText,
    CURRENT_WINDOW,
    drawVowelChart,
    TRAIL_WINDOW,
    vowelChartDescription,
  } from '../graph/vowelChart'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'

  /**
   * 모음 지도와 그 위의 F1·F2 숫자 (iOS `VowelChartView`). 지금 내는 소리를 큰 점으로, 최근 1.5초를 흐린 꼬리로 보여 준다.
   * 녹음을 다시 들을 때는 재생 위치를 따라가고, 모음을 재는 동안에는 재는 소리를 보여 준다.
   * 탭이 숨어 있으면(`active`가 false) 그리지 않는다.
   */
  let { active, caption }: { active: boolean; caption: string } = $props()

  let canvas: HTMLCanvasElement
  let width = $state(0)
  let current: VowelPoint | null = $state(null)
  let description = $state('')

  const comparison = $derived(comparisonText(current, settings.vowelMap, settings.selectedVowel))

  let dirty = true
  let colors: GraphColors | null = null
  let fontFamily = 'system-ui'
  let lastDescriptionAt = 0
  let animationFrame = 0

  // 지도 모양을 바꾸는 값이 바뀌면 멈춰 있어도 다시 그린다.
  $effect(() => {
    void [settings.vowelMap, settings.selectedVowel, session.clock, session.phase, width, active]
    dirty = true
  })

  function readColors(): GraphColors {
    const style = getComputedStyle(canvas)
    const value = (name: string) => style.getPropertyValue(name).trim()
    fontFamily = getComputedStyle(document.body).fontFamily
    return {
      voice: value('--voice'),
      inactive: value('--inactive'),
      target: value('--target'),
      reference: value('--reference'),
      secondary: value('--secondary'),
      primary: value('--text'),
    }
  }

  function frame() {
    animationFrame = requestAnimationFrame(frame)
    if (!active) return
    const now = session.now()
    // 재는 동안은 재기용 기록(마지막 녹음에는 섞지 않는 점)을, 그 밖에는 그래프와 같은 기록을 본다.
    const isMeasuring = session.phase.kind === 'measuring'
    const history = isMeasuring ? session.measuringHistory : session.history
    const end = isMeasuring ? now : clockEndTime(session.clock, now)
    const moving = isMeasuring || clockIsMoving(session.clock)
    if (!moving && !dirty) return

    current = VowelSpace.current(history.readingsIn({ lower: end - CURRENT_WINDOW, upper: end }))
    if (canvas && width > 0) {
      const ratio = globalThis.devicePixelRatio || 1
      const pixelWidth = Math.round(width * ratio)
      const pixelHeight = Math.round(CHART_HEIGHT * ratio)
      if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
        canvas.width = pixelWidth
        canvas.height = pixelHeight
      }
      colors ??= readColors()
      const ctx = canvas.getContext('2d')
      if (ctx) {
        const trail = history.readingsIn({ lower: end - TRAIL_WINDOW, upper: end })
        const scene = { current, trail, end, map: settings.vowelMap, selected: settings.selectedVowel }
        drawVowelChart(ctx, width, CHART_HEIGHT, ratio, scene, colors, fontFamily)
      }
      dirty = false
    }

    // 화면 읽기 프로그램용 설명은 0.5초마다만 고친다.
    if (performance.now() - lastDescriptionAt > 500) {
      lastDescriptionAt = performance.now()
      description = vowelChartDescription(current, settings.vowelMap)
    }
  }

  onMount(() => {
    // 밝은·어두운 모드가 바뀌면 색을 다시 읽는다.
    const scheme = matchMedia('(prefers-color-scheme: dark)')
    const onScheme = () => {
      colors = null
      dirty = true
    }
    scheme.addEventListener('change', onScheme)
    animationFrame = requestAnimationFrame(frame)
    return () => {
      cancelAnimationFrame(animationFrame)
      scheme.removeEventListener('change', onScheme)
    }
  })
</script>

<div class="chart">
  <div class="numbers">
    <p class="values">
      <span class="value-group">
        <span class="name">F1</span>
        <span class="value" class:dimmed={current?.isF1Uncertain === true}>{current === null ? '–' : Math.round(current.f1)}</span>
        <span class="unit">Hz</span>
      </span>
      <span class="value-group">
        <span class="name">F2</span>
        <span class="value">{current === null ? '–' : Math.round(current.f2)}</span>
        <span class="unit">Hz</span>
      </span>
    </p>
    <p class="caption">
      {current?.isF1Uncertain === true ? '목소리가 높아 F1(세로)은 정확하지 않을 수 있어요' : caption}
    </p>
    {#if comparison !== null}
      <p class="comparison">{comparison}</p>
    {/if}
  </div>

  <div class="map" bind:clientWidth={width} role="img" aria-label="모음 지도" aria-describedby="vowel-description">
    <canvas bind:this={canvas} aria-hidden="true" style:height={`${CHART_HEIGHT}px`}></canvas>
    <span id="vowel-description" class="visually-hidden">{description}</span>
  </div>
</div>

<style>
  .chart {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .numbers {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }
  .numbers p {
    margin: 0;
  }
  .values {
    display: flex;
    gap: 16px;
    align-items: baseline;
  }
  .value-group {
    display: flex;
    align-items: baseline;
    gap: 4px;
  }
  .name {
    color: var(--secondary);
    font-size: 0.95rem;
    font-weight: 500;
  }
  .value {
    font-size: 34px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .value.dimmed {
    color: var(--secondary);
  }
  .unit,
  .caption {
    color: var(--secondary);
    font-size: 0.8rem;
  }
  .caption {
    text-align: center;
  }
  .comparison {
    color: var(--reference);
    font-size: 0.8rem;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .map {
    background: var(--card);
    border-radius: 12px;
    overflow: hidden;
  }
  canvas {
    display: block;
    width: 100%;
  }
</style>
