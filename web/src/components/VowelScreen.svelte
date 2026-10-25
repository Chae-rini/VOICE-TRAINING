<script lang="ts">
  import { untrack } from 'svelte'
  import { TEST_VOWEL_FORMANTS, type InputSource } from '../audio/micInput'
  import { newRecordId } from '../model/records'
  import { settings } from '../model/settings.svelte'
  import { store } from '../storage/recordStore.svelte'
  import { VowelMaps } from '../model/vowelMap'
  import { session } from '../practice/session.svelte'
  import { KOREAN_VOWELS } from '../text/korean'
  import StorageNotice from './StorageNotice.svelte'
  import VowelChart from './VowelChart.svelte'

  /**
   * [모음] 화면 (iOS `VowelMapScreen`): 실시간 모음 지도, 내 모음 지도 재기, 보는 법.
   * 녹음·듣기 조작은 [높이] 화면과 같은 아래 영역(`PracticeControls`)을 함께 쓴다.
   */
  let { active }: { active: boolean } = $props()

  const isDev = import.meta.env.DEV
  let fileInput: HTMLInputElement
  /** 방금 잰 결과 안내. `warning`이면 저장하지 못한 안내 (색을 다르게) */
  let message: { text: string; warning: boolean } | null = $state(null)

  const selected = $derived(settings.selectedVowel)
  const map = $derived(settings.vowelMap)
  const isMeasuringVowel = $derived(session.phase.kind === 'measuring' && session.measuringVowel !== null)

  const caption = $derived.by(() => {
    if (session.busy === 'starting') return '마이크를 켜는 중…'
    switch (session.phase.kind) {
      case 'recording':
        return '지금 내는 모음'
      case 'listening':
      case 'replaying':
        return '녹음을 다시 듣는 중'
      case 'countdown':
        return '곧 다시 녹음해요'
      case 'measuring':
        return session.measuringVowel !== null ? `‘${session.measuringVowel}’ 길게 내는 중` : '내 목소리 재는 중'
      case 'idle':
        return session.lastTake !== null ? '마지막 녹음' : '‘반복 루프 재생’을 누르고 모음을 길게 내 보세요'
    }
  })

  // 모음 하나를 다 재면 지도에 저장한다 (이 기기 안에만). 같은 모음을 다시 재면 새 값으로 바뀐다.
  $effect(() => {
    const result = session.vowelResult
    if (result === null) return
    untrack(() => {
      if (result.entry !== null) {
        // 지도에는 마지막 값(설정 파일), 이력에는 잴 때마다 하나씩(기록 파일)
        void store.addRecord('vowelHistory', { id: newRecordId(), vowel: result.vowel, ...result.entry })
        settings.setVowelEntry(result.vowel, result.entry)
        const f1 = Math.round(result.entry.f1)
        const f2 = Math.round(result.entry.f2)
        message = { text: `‘${result.vowel}’를 저장했어요 · F1 ${f1} · F2 ${f2} Hz`, warning: false }
      } else {
        message = {
          text: `목소리가 너무 짧게 잡혔어요. ‘${result.vowel}’를 3초 동안 끊지 말고 길게 내 보세요.`,
          warning: true,
        }
      }
      session.clearVowelResult()
    })
  })

  function measure(source: InputSource) {
    message = null
    void session.startMeasuringVowel(selected, source)
  }

  function openFilePicker() {
    message = null
    fileInput.click()
  }

  function onFileChosen() {
    const file = fileInput.files?.[0]
    fileInput.value = ''
    if (file) void session.measureVowelFromFile(selected, file)
  }
</script>

<div class="screen">
  <StorageNotice />
  <VowelChart {active} {caption} />

  <section class="card" aria-labelledby="my-map-title">
    <div class="header">
      <h2 id="my-map-title">내 모음 지도</h2>
      <span class="count">{VowelMaps.measuredCount(map)}/7개 잼</span>
    </div>
    <p class="secondary">모음을 고르고 3초 동안 길게 내면 지도에 내 위치로 남아요. 다시 재면 새 값으로 바뀌어요.</p>

    <div class="vowels" role="group" aria-label="모음 고르기">
      {#each KOREAN_VOWELS as vowel (vowel)}
        <button
          class="vowel"
          class:selected={vowel === selected}
          aria-pressed={vowel === selected}
          aria-label={`${vowel}${map[vowel] === undefined ? '' : ', 잼'}`}
          onclick={() => {
            settings.setSelectedVowel(vowel)
            message = null
          }}
        >
          <span class="letter">{vowel}</span>
          <span class="mark" aria-hidden="true">{map[vowel] === undefined ? '○' : '✓'}</span>
        </button>
      {/each}
    </div>

    <!-- 내 모음 지도는 내 기준이라 재기 버튼도 보라(지도의 원과 같은 색) -->
    <div class="actions">
      <button class="fill" onclick={() => measure({ kind: 'mic' })} disabled={session.isRunning}>
        🎙 ‘{selected}’ 재기 · 3초
      </button>
      <button class="outline" onclick={openFilePicker} disabled={session.isRunning}>📁 파일로</button>
    </div>
    {#if isDev}
      <button
        class="outline dev"
        onclick={() => measure({ kind: 'testTone', testToneHz: 150, formants: TEST_VOWEL_FORMANTS })}
        disabled={session.isRunning}
      >
        테스트 모음으로 재기 (개발용)
      </button>
    {/if}

    {#if isMeasuringVowel}
      <progress
        max={session.measuringSeconds}
        value={session.measuringSeconds - session.remaining}
        aria-label={`‘${session.measuringVowel}’ 재는 중`}
      ></progress>
    {:else if session.busy === 'analyzing'}
      <p class="secondary" role="status">녹음을 분석하는 중…</p>
    {:else if message !== null}
      <p class={message.warning ? 'warning' : 'saved'} role="status">{message.text}</p>
    {/if}
  </section>

  <section class="card guide" aria-labelledby="guide-title">
    <h2 id="guide-title">모음 지도 보는 법</h2>
    <p>
      목과 입안이 울리는 두 주파수(포먼트)로 지금 내는 모음의 위치를 보여 줘요. ‘아·에·이·오·우·으·어’ 중 하나를 2~3초 길게 내
      보세요.
    </p>
    <p>• 가로(F2): 혀가 앞쪽일수록 왼쪽, 뒤쪽일수록 오른쪽</p>
    <p>• 세로(F1): 입을 좁게 열수록 위, 크게 열수록 아래</p>
    <p>• 분홍 점은 지금 내는 소리, 보라 원은 내가 잰 모음이에요. 위에서 고른 모음을 쟀으면 지금 소리와의 차이가 숫자로 나와요.</p>
    <p class="secondary">
      같은 모음도 사람마다 위치가 달라서, 정해진 정답 위치는 없어요. 목소리가 높을수록 세로(F1)는 덜 정확하고 가로(F2)가 더 믿을
      만해요. 이때는 점이 속이 빈 점선 원으로 바뀌어요.
    </p>
    <p class="secondary">소리는 이 기기 안에서만 분석하고 어디로도 보내지 않아요. 울림은 의료 기기가 아니에요.</p>
  </section>
</div>

<input bind:this={fileInput} type="file" accept="audio/*" hidden onchange={onFileChosen} />

<style>
  .screen {
    height: 100%;
    overflow-y: auto;
    box-sizing: border-box;
    padding: max(12px, env(safe-area-inset-top)) 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 0.85rem;
  }
  .card p {
    margin: 0;
  }
  h2 {
    margin: 0;
    font-size: 0.95rem;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .count,
  .secondary {
    color: var(--secondary);
  }
  .count {
    font-variant-numeric: tabular-nums;
  }
  .vowels {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    gap: 6px;
  }
  .vowel {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 6px 0;
    border-radius: 10px;
    background: var(--fill);
    color: var(--inactive);
  }
  .vowel.selected {
    background: color-mix(in srgb, var(--reference) 18%, transparent);
    color: var(--reference);
    outline: 1.5px solid var(--reference);
  }
  .letter {
    font-size: 1.05rem;
    font-weight: 600;
    color: var(--text);
  }
  .vowel.selected .letter {
    color: var(--reference);
  }
  .mark {
    font-size: 0.7rem;
  }
  .actions {
    display: flex;
    gap: 10px;
  }
  .fill {
    flex: 1;
    padding: 12px 16px;
    background: var(--reference-fill);
    color: #ffffff;
  }
  .outline {
    flex: none;
    padding: 12px 16px;
    background: color-mix(in srgb, var(--reference) 14%, transparent);
    color: var(--reference);
  }
  .outline.dev {
    font-size: 0.75rem;
    padding: 6px 12px;
    align-self: flex-start;
  }
  progress {
    width: 100%;
    accent-color: var(--reference);
  }
  .saved {
    color: var(--record);
  }
  .warning {
    color: var(--warning);
  }
  .guide p {
    font-size: 0.8rem;
  }
</style>
