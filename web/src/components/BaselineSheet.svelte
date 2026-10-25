<script lang="ts">
  import { onMount } from 'svelte'
  import type { InputSource } from '../audio/micInput'
  import { Baseline, TargetRange, type VoiceBaseline } from '../model/practice'
  import { settings } from '../model/settings.svelte'
  import { session } from '../practice/session.svelte'

  /**
   * "내 목소리 재기": 연습 문장을 편하게 읽는 10초로 기준 목소리를 잰다 (iOS `BaselineMeasureView`).
   * 결과는 중앙값과 범위만 보여 주고, 높다·낮다 같은 평가는 하지 않는다.
   * 저장하면 그래프에 기준선(점선)이 생기고, 원하면 목표 범위를 기준 ±20 Hz로 맞춘다.
   */
  let { open, onClose }: { open: boolean; onClose: () => void } = $props()

  let dialog: HTMLDialogElement
  const isDev = import.meta.env.DEV
  /** 목표 범위를 기준에 맞출지. 저장해 둔 목표 범위가 있으면 처음에는 꺼 둔다 (저절로 바뀌지 않게). */
  let applyToTarget = $state(settings.target === null)
  let frequency: number | null = $state(null)
  let animationFrame = 0

  const isMeasuring = $derived(session.phase.kind === 'measuring' || (session.busy === 'starting' && open))
  const isAnalyzing = $derived(session.busy === 'analyzing')
  let fileInput: HTMLInputElement

  function onFileChosen() {
    const file = fileInput.files?.[0]
    fileInput.value = ''
    if (file) void session.measureFromFile(file)
  }
  const measurement = $derived(session.measurement)

  $effect(() => {
    if (open && !dialog.open) {
      applyToTarget = settings.target === null
      dialog.showModal()
    } else if (!open && dialog.open) {
      dialog.close()
    }
  })

  onMount(() => {
    // 재는 동안 지금 높이를 보여 준다
    const tick = () => {
      frequency = session.phase.kind === 'measuring' ? session.measuringHistory.frequencyAt(session.now()) : null
      animationFrame = requestAnimationFrame(tick)
    }
    animationFrame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(animationFrame)
  })

  function start(source: InputSource) {
    void session.startMeasuring(source)
  }

  async function close() {
    await session.cancelMeasuring()
    onClose()
  }

  function save(baseline: VoiceBaseline) {
    settings.setBaseline(baseline, applyToTarget)
    void session.cancelMeasuring()
    onClose()
  }

  function targetChangeDescription(baseline: VoiceBaseline): string {
    const next = TargetRange.label(Baseline.initialTarget(baseline)).replace(' – ', '–')
    const current = settings.target
    if (current !== null) {
      const currentText = TargetRange.label(current).replace(' – ', '–')
      return applyToTarget ? `지금 ${currentText} → ${next}` : `지금 목표 범위(${currentText})를 그대로 둬요`
    }
    return applyToTarget ? `${next}로 시작해요. 슬라이더로 위든 아래든 옮길 수 있어요.` : '목표 범위 없이 기준만 저장해요'
  }
</script>

<dialog bind:this={dialog} oncancel={(event) => { event.preventDefault(); if (!isMeasuring) void close() }} aria-labelledby="baseline-title">
  <header>
    <button class="plain" onclick={close}>{measurement === null ? '나중에' : '닫기'}</button>
    <h2 id="baseline-title">내 목소리 재기</h2>
    <span></span>
  </header>

  <div class="content">
    <p class="secondary">평소에 편하게 말하는 목소리를 재요. 이 높이를 기준으로 목표 범위를 정할 수 있어요.</p>
    {#if settings.baseline !== null && measurement === null && !isMeasuring}
      <p class="secondary small">지금 저장된 기준: {Math.round(settings.baseline.median)} Hz</p>
    {/if}

    <div class="card">
      <p class="secondary small">10초 동안 이 문장을 평소처럼 두세 번 읽어 주세요.</p>
      <p class="sentence">{Baseline.readingSentence}</p>
    </div>

    {#if isMeasuring}
      <div class="measuring">
        <p class="number"><span>{frequency === null ? '–' : Math.round(frequency)}</span> <small>Hz</small></p>
        <progress max={Baseline.recordingSeconds} value={Baseline.recordingSeconds - session.remaining} aria-label="녹음 중"
        ></progress>
        <p class="secondary small">녹음 중 · {Math.ceil(session.remaining)}초 남음</p>
        <button class="plain" onclick={() => session.cancelMeasuring()}>그만두기</button>
      </div>
    {:else if isAnalyzing}
      <p class="secondary">녹음을 분석하는 중…</p>
    {:else if measurement?.kind === 'tooLittleVoice'}
      <div class="result">
        <h3>ⓘ 목소리가 거의 잡히지 않았어요.</h3>
        <p class="secondary">조용한 곳에서 위 문장을 평소 목소리로 소리 내어 다시 읽어 주세요.</p>
        <button class="fill" onclick={() => session.cancelMeasuring()}>다시 재기</button>
      </div>
    {:else if measurement?.kind === 'measured'}
      {@const baseline = measurement.baseline}
      <div class="result">
        <h3>잰 결과</h3>
        <div class="stats">
          <div><span class="secondary small">중앙</span><strong>{Math.round(baseline.median)} Hz</strong></div>
          <div><span class="secondary small">범위</span><strong>{Math.round(baseline.low)}–{Math.round(baseline.high)} Hz</strong></div>
        </div>
        <p class="secondary small">범위는 잡힌 높이 중 아래 10%~위 10% 사이예요.</p>
        <p class="secondary small">
          {baseline.f2 === null
            ? '포먼트가 충분히 잡히지 않아 공명 밝기 기준은 저장하지 않아요.'
            : `공명 밝기 기준(F2 중앙값): ${Math.round(baseline.f2)} Hz`}
        </p>
        <label class="toggle">
          <input type="checkbox" bind:checked={applyToTarget} />
          <span>
            목표 범위를 이 기준에 맞추기
            <span class="secondary small block">{targetChangeDescription(baseline)}</span>
          </span>
        </label>
        <button class="fill" onclick={() => save(baseline)}>이 값으로 저장</button>
        <button class="plain" onclick={() => session.cancelMeasuring()}>다시 재기</button>
      </div>
    {:else}
      <div class="start">
        <button class="fill" onclick={() => start({ kind: 'mic' })} disabled={session.isRunning}>🎙 10초 재기</button>
        <button onclick={() => fileInput.click()} disabled={session.isRunning}>📁 녹음 파일로 재기</button>
        {#if isDev}
          <button onclick={() => start({ kind: 'testTone', testToneHz: 180 })} disabled={session.isRunning}>
            테스트 음 180 Hz로 재기 (개발용)
          </button>
        {/if}
        {#if session.isRunning}
          <p class="secondary small">연습 중에는 잴 수 없어요. 연습을 멈춘 뒤 다시 눌러 주세요.</p>
        {/if}
        {#if session.errorMessage !== null}
          <p class="error small">{session.errorMessage}</p>
        {/if}
      </div>
    {/if}
  </div>
  <input bind:this={fileInput} type="file" accept="audio/*" hidden onchange={onFileChosen} />
</dialog>

<style>
  dialog {
    width: min(480px, calc(100vw - 32px));
    max-height: calc(100dvh - 48px);
    padding: 0;
    border: none;
    border-radius: 16px;
    background: var(--background);
    color: var(--text);
  }
  dialog::backdrop {
    background: rgb(0 0 0 / 0.4);
  }
  header {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--divider);
  }
  h2 {
    margin: 0;
    font-size: 1rem;
  }
  h3 {
    margin: 0;
    font-size: 1rem;
  }
  .content {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 16px;
  }
  .content p {
    margin: 0;
  }
  .secondary {
    color: var(--secondary);
  }
  .small {
    font-size: 0.85rem;
  }
  .block {
    display: block;
  }
  .error {
    color: #ff3b30;
  }
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .sentence {
    font-size: 1.25rem;
    font-weight: 500;
    word-break: keep-all;
  }
  .measuring {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }
  .number {
    font-size: 48px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .number small {
    font-size: 1rem;
    color: var(--secondary);
  }
  progress {
    width: 100%;
    accent-color: var(--reference);
  }
  .result,
  .start {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .stats {
    display: grid;
    grid-template-columns: 1fr 1fr;
  }
  .stats div {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .stats strong {
    font-size: 1.25rem;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .toggle {
    display: flex;
    gap: 10px;
    align-items: flex-start;
  }
  .toggle input {
    margin-top: 4px;
    accent-color: var(--reference-fill);
  }
  button.fill {
    background: var(--reference-fill);
    color: #ffffff;
  }
  button.plain {
    background: none;
    color: var(--reference);
    justify-self: start;
  }
</style>
