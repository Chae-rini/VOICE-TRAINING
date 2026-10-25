<script lang="ts">
  import { onMount } from 'svelte'
  import { clockEndTime, clockIsMoving, clockWindow } from '../dsp/pitchHistory'
  import { graphRange } from '../dsp/pitchScale'
  import { contains } from '../dsp/range'
  import { LevelMeter, ResonanceMeter, type ResonanceReading } from '../dsp/voiceMeters'
  import { graphDescription, graphLabel, meterDescription } from '../graph/descriptions'
  import { drawPitchGraph, type GraphColors } from '../graph/pitchGraph'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'

  /**
   * [높이] 화면 위에 고정되는 부분: 지금 높이 숫자, 그래프, 음량·공명 막대 (iOS `PitchGraphView`).
   * 화면을 그릴 때마다 최근 점으로 숫자를 고치고 그래프를 다시 그린다. 멈춰 있으면 바뀐 것이 있을 때만 그린다.
   */
  let {
    compact,
    height,
    caption,
  }: {
    /** 대본 읽기 모드: 그래프를 낮게, 큰 숫자를 한 줄로 */
    compact: boolean
    /** [px] 그래프 높이 */
    height: number
    caption: string
  } = $props()

  let canvas: HTMLCanvasElement
  let width = $state(0)
  let frequency: number | null = $state(null)
  let level: number | null = $state(null)
  let isLoud = $state(false)
  let resonance: ResonanceReading | null = $state(null)
  let description = $state('')
  let label = $state('')

  const inTarget = $derived(frequency !== null && settings.target !== null && contains(settings.target, frequency))
  const captionText = $derived(inTarget ? `${caption} · 목표 범위 안` : caption)

  let dirty = true
  let colors: GraphColors | null = null
  let fontFamily = 'system-ui'
  let lastDescriptionAt = 0

  // 그래프 모양을 바꾸는 값이 바뀌면 멈춰 있어도 다시 그린다.
  $effect(() => {
    void [settings.target, settings.baseline, settings.practiceDuration, session.clock, height, width, compact]
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
    const now = session.now()
    const clock = session.clock
    const endTime = clockEndTime(clock, now)
    const window = clockWindow(clock, now) ?? session.idleWindow(endTime, settings.practiceDuration)
    const history = session.history
    const moving = clockIsMoving(clock)
    const isLive = clock.kind === 'live'

    frequency = isLive ? history.frequencyAt(endTime) : clock.kind === 'replay' ? history.frequencyAt(endTime) : null
    // 막대는 최근 3초 남짓만 꺼내 계산한다. 움직이지 않으면 비운다 (iOS와 같다).
    const recent = moving ? history.readingsIn({ lower: endTime - LevelMeter.loudSeconds - 0.2, upper: endTime }) : []
    level = LevelMeter.smoothedLevel(recent, endTime)
    // 아주 큰 소리 안내는 지금 녹음하는 동안만
    isLoud = isLive && LevelMeter.isSustainedLoud(recent, endTime)
    resonance = ResonanceMeter.current(recent, endTime)

    if ((moving || dirty) && canvas && width > 0) {
      const ratio = globalThis.devicePixelRatio || 1
      const pixelWidth = Math.round(width * ratio)
      const pixelHeight = Math.round(height * ratio)
      if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
        canvas.width = pixelWidth
        canvas.height = pixelHeight
      }
      colors ??= readColors()
      const ctx = canvas.getContext('2d')
      if (ctx) {
        drawPitchGraph(
          ctx,
          width,
          height,
          ratio,
          {
            history,
            window,
            endTime,
            target: settings.target,
            baselineMedian: settings.baseline?.median ?? null,
            isReplaying: clock.kind === 'replay',
          },
          colors,
          fontFamily,
        )
      }
      dirty = false
    }

    // 화면 읽기 프로그램용 설명은 0.5초마다만 고친다.
    if (performance.now() - lastDescriptionAt > 500) {
      lastDescriptionAt = performance.now()
      label = graphLabel(window)
      description = graphDescription({
        frequency,
        window,
        endTime,
        axis: graphRange(settings.target),
        target: settings.target,
        baselineMedian: settings.baseline?.median ?? null,
        isReplaying: clock.kind === 'replay',
      })
    }
    animationFrame = requestAnimationFrame(frame)
  }

  let animationFrame = 0
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

  const baselineF2 = $derived(settings.baseline?.f2 ?? null)
  const meterText = $derived(meterDescription(level, isLoud, resonance, baselineF2))
</script>

<div class="panel" class:compact>
  {#if compact}
    <p class="pitch-line">
      <span class="value" class:in-target={inTarget}>{frequency === null ? '–' : Math.round(frequency)}</span>
      <span class="unit">Hz</span>
      <span class="caption">{captionText}</span>
    </p>
  {:else}
    <div class="pitch">
      <p class="number">
        <span class="value" class:in-target={inTarget}>{frequency === null ? '–' : Math.round(frequency)}</span>
        <span class="unit">Hz</span>
      </p>
      <p class="caption">{captionText}</p>
    </div>
  {/if}

  <div
    class="graph"
    bind:clientWidth={width}
    style:height={`${height}px`}
    role="img"
    aria-label={label}
    aria-describedby="graph-description"
  >
    <canvas bind:this={canvas} aria-hidden="true" style:height={`${height}px`}></canvas>
    <span id="graph-description" class="visually-hidden">{description}</span>
  </div>

  <div class="meters" role="group" aria-label="음량과 공명 밝기">
    <span class="visually-hidden">{meterText}</span>
    <div class="row" aria-hidden="true">
      <span class="title">음량</span>
      <div class="bar">
        <div
          class="fill"
          class:loud={isLoud}
          style:width={`${LevelMeter.position(level ?? LevelMeter.range.lower) * 100}%`}
        ></div>
      </div>
      <span class="meter-value">{level === null ? '– dBFS' : `${Math.round(level)} dBFS`}</span>
    </div>
    <div class="row" aria-hidden="true">
      <span class="title">공명</span>
      {#if baselineF2 !== null}
        <span class="end">어두운</span>
        <div class="bar resonance">
          <div class="center"></div>
          {#if resonance !== null}
            <div
              class="dot"
              class:uncertain={resonance.isUncertain}
              style:left={`${ResonanceMeter.position(resonance.f2, baselineF2) * 100}%`}
            ></div>
          {/if}
        </div>
        <span class="end">밝은</span>
      {:else}
        <span class="hint">내 목소리 재기를 하면 기준이 생겨요</span>
      {/if}
      <span class="meter-value">{resonance === null ? 'F2 –' : `F2 ${Math.round(resonance.f2)}`}</span>
    </div>
    {#if isLoud}
      <p class="loud-note" aria-hidden="true">⚠︎ 소리가 꽤 커요. 목에 무리가 없는지 확인해 보세요.</p>
    {/if}
  </div>
</div>

<style>
  .panel {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .panel.compact {
    gap: 4px;
  }
  .pitch {
    text-align: center;
  }
  .number,
  .pitch-line {
    margin: 0;
    display: flex;
    align-items: baseline;
    gap: 4px;
  }
  .number {
    justify-content: center;
  }
  .value {
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    font-size: 56px;
    line-height: 1.05;
  }
  .compact .value {
    font-size: 28px;
  }
  .value.in-target {
    color: var(--voice);
  }
  .unit {
    color: var(--secondary);
    font-size: 1.25rem;
  }
  .compact .unit {
    font-size: 0.95rem;
  }
  .caption {
    margin: 2px 0 0;
    color: var(--secondary);
    font-size: 0.8rem;
  }
  .pitch-line .caption {
    margin: 0 0 0 4px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }
  .graph {
    position: relative;
    background: var(--card);
    border-radius: 12px;
    overflow: hidden;
  }
  canvas {
    display: block;
    width: 100%;
  }
  .meters {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.75rem;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 16px;
  }
  .title {
    color: var(--secondary);
    width: 30px;
    flex: none;
  }
  .bar {
    position: relative;
    flex: 1;
    height: 6px;
    border-radius: 3px;
    background: var(--fill);
  }
  .fill {
    height: 100%;
    border-radius: 3px;
    background: color-mix(in srgb, var(--secondary) 70%, transparent);
  }
  .fill.loud {
    background: var(--warning);
  }
  .resonance .center {
    position: absolute;
    left: 50%;
    top: -3px;
    width: 2px;
    height: 12px;
    margin-left: -1px;
    border-radius: 1px;
    background: var(--reference);
  }
  .dot {
    position: absolute;
    top: 50%;
    width: 10px;
    height: 10px;
    margin: -5px 0 0 -5px;
    border-radius: 50%;
    background: var(--voice);
  }
  .dot.uncertain {
    background: transparent;
    border: 1.5px dashed var(--voice);
    box-sizing: border-box;
  }
  .end,
  .hint {
    color: var(--secondary);
    font-size: 0.7rem;
    flex: none;
  }
  .hint {
    flex: 1;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meter-value {
    width: 64px;
    flex: none;
    text-align: right;
    color: var(--secondary);
    font-size: 0.7rem;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .loud-note {
    margin: 0;
    color: var(--warning);
  }
</style>
