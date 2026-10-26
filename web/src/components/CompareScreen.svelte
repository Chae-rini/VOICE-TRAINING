<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte'
  import { GraphWindow } from '../dsp/graphWindow'
  import { PitchSummary } from '../dsp/pitchSummary'
  import { medianDifferenceText, rangeSemitones } from '../model/comparison'
  import { languageLabel, recordingDisplayTitle, type RecordingRecord } from '../model/records'
  import { settings } from '../model/settings.svelte'
  import { isNativeApp } from '../platform/app'
  import { ComparePlayer, type CompareSide } from '../practice/comparePlayer.svelte'
  import { session } from '../practice/session.svelte'
  import { store } from '../storage/recordStore.svelte'
  import { formatShortDateTime } from '../text/dates'
  import CompareChart from './CompareChart.svelte'
  import { navigation } from './navigation.svelte'

  /**
   * 두 녹음 비교 (iOS `RecordingCompareView`): 남긴 녹음 두 개(A·B)를 골라 수치를 나란히 보고, 높이 분포를 겹쳐 보고, 번갈아 듣는다.
   * 어느 쪽이 낫다는 말은 하지 않고 차이만 보여 준다 (원칙 3). A는 내 기준 색(보라), B는 기록 색(초록) — 분홍·파랑을 전/후 짝으로 쓰지 않는다.
   */
  let {
    recordings,
    initialA,
    initialB,
    onBack,
  }: {
    /** 고를 수 있는 녹음 (최근 것부터) */
    recordings: readonly RecordingRecord[]
    initialA: string
    initialB: string
    onBack: () => void
  } = $props()

  // 처음 고른 짝은 화면을 열 때 한 번만 받는다 (그 뒤로는 이 화면에서 바꾼다)
  // svelte-ignore state_referenced_locally
  let aId = $state(initialA)
  // svelte-ignore state_referenced_locally
  let bId = $state(initialB)
  const player = new ComparePlayer()
  let remaining = $state(0)
  let ticker = 0

  const a = $derived(recordings.find((r) => r.id === aId))
  const b = $derived(recordings.find((r) => r.id === bId))
  /** 연습 중이면 재생을 막는다 (연습과 재생이 같은 마이크·스피커를 쓰므로) */
  const canPlay = $derived(!session.isRunning)

  // 고르는 녹음이 바뀔 때마다 그 소리를 읽어 분석한다. 읽는 동안 바뀌는 재생기 상태(읽는 중·실패)에는 따라 돌지 않게 untrack.
  $effect(() => {
    const fileName = a?.fileName
    if (fileName !== undefined) untrack(() => void player.load('A', store.readRecording(fileName)))
  })
  $effect(() => {
    const fileName = b?.fileName
    if (fileName !== undefined) untrack(() => void player.load('B', store.readRecording(fileName)))
  })
  // 연습을 시작하거나 다른 탭으로 가면 멈춘다
  $effect(() => {
    if (session.isRunning || navigation.tab !== 'history') untrack(() => player.stop())
  })

  // 앱에서는 다른 앱으로 가거나 전화가 와서 화면이 가려지면 멈춘다 (연습은 nativeApp이 멈춘다)
  const stopWhenHidden = () => {
    if (isNativeApp() && document.visibilityState === 'hidden') player.stop()
  }

  onMount(() => {
    const tick = () => {
      remaining = player.playing === null ? 0 : Math.max(0, player.endsAt - session.now())
    }
    ticker = window.setInterval(tick, 200)
    document.addEventListener('visibilitychange', stopWhenHidden)
  })
  onDestroy(() => {
    clearInterval(ticker)
    document.removeEventListener('visibilitychange', stopWhenHidden)
    player.stop()
  })

  /**
   * 앱에서 녹음한 것은 이름에 날짜가 있고, 불러온 파일은 이름 뒤에 날짜를 붙인다.
   * 같은 분에 남긴 녹음은 이름이 같아지므로 메모가 있으면 뒤에 붙인다.
   */
  function optionLabel(record: RecordingRecord): string {
    const recordedAt = new Date(record.recordedAt)
    const name =
      record.title === '' ? recordingDisplayTitle(record) : `${record.title} · ${recordedAt.getMonth() + 1}월 ${recordedAt.getDate()}일`
    const memo = record.memo.length > 20 ? `${record.memo.slice(0, 20)}…` : record.memo
    return memo === '' ? name : `${name} · ${memo}`
  }

  function swap() {
    ;[aId, bId] = [bId, aId]
  }

  function toggle(side: CompareSide) {
    if (player.playing === side) player.stop()
    else player.play(side)
  }

  const rangeText = (r: RecordingRecord) => `${Math.round(r.pitch.p10)}–${Math.round(r.pitch.p90)} Hz`
  const semitoneText = (r: RecordingRecord) => `반음 ${rangeSemitones(r.pitch.p10, r.pitch.p90).toFixed(1)}개`
  const targetText = (r: RecordingRecord) =>
    r.pitch.target === null ? '정하지 않음' : `${Math.trunc(r.pitch.target.lower)}–${Math.trunc(r.pitch.target.upper)} Hz`
  const percentText = (r: RecordingRecord) =>
    r.pitch.inTargetFraction === null ? '–' : `${Math.round(r.pitch.inTargetFraction * 100)}%`
</script>

{#snippet dateCell(record: RecordingRecord)}
  {@const parts = formatShortDateTime(new Date(record.recordedAt)).split(' ')}
  <!-- 날짜와 시각을 두 줄로 (한 줄이면 칸이 좁아 잘린다) -->
  <td>{parts.slice(0, 2).join(' ')}<br /><span class="secondary">{parts.slice(2).join(' ')}</span></td>
{/snippet}

<div class="compare">
  <button class="plain back" onclick={onBack}>‹ 기록</button>
  <h2>두 녹음 비교</h2>

  <section class="card">
    <label class="pick">
      <span class="side a"><span class="dot"></span>A</span>
      <select bind:value={aId} aria-label="A 녹음">
        {#each recordings as record (record.id)}
          <option value={record.id}>{optionLabel(record)}</option>
        {/each}
      </select>
    </label>
    <label class="pick">
      <span class="side b"><span class="dot"></span>B</span>
      <select bind:value={bId} aria-label="B 녹음">
        {#each recordings as record (record.id)}
          <option value={record.id}>{optionLabel(record)}</option>
        {/each}
      </select>
    </label>
    <button class="plain" onclick={swap}>⇅ A와 B 바꾸기</button>
    <p class="note">
      {aId === bId ? '같은 녹음을 골랐어요. 다른 녹음을 골라 보세요.' : '처음에는 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B)을 골라 둬요.'}
    </p>
  </section>

  {#if a !== undefined && b !== undefined}
    <section class="card">
      <h3>나란히 보기</h3>
      <table>
        <thead>
          <tr><th></th><th><span class="side a"><span class="dot"></span>A</span></th><th><span class="side b"><span class="dot"></span>B</span></th></tr>
        </thead>
        <tbody>
          <!-- A와 B가 같은 녹음일 수도 있어서 반복 대신 두 칸을 따로 그린다 (키가 겹치지 않게) -->
          <tr><th>남긴 때</th>{@render dateCell(a)}{@render dateCell(b)}</tr>
          <tr><th>말한 언어</th><td>{languageLabel(a.language)}</td><td>{languageLabel(b.language)}</td></tr>
          <tr>
            <th>길이</th><td>{PitchSummary.durationLabel(a.pitch.duration)}</td><td>{PitchSummary.durationLabel(b.pitch.duration)}</td>
          </tr>
          <tr><th>중앙</th><td>{Math.round(a.pitch.median)} Hz</td><td>{Math.round(b.pitch.median)} Hz</td></tr>
          <tr><th>범위</th><td>{rangeText(a)}</td><td>{rangeText(b)}</td></tr>
          <tr><th>높낮이 폭</th><td>{semitoneText(a)}</td><td>{semitoneText(b)}</td></tr>
          <tr><th>그때 목표</th><td>{targetText(a)}</td><td>{targetText(b)}</td></tr>
          <tr><th>목표 범위 안</th><td>{percentText(a)}</td><td>{percentText(b)}</td></tr>
          <tr><th>목소리 잡힌 시간</th><td>{a.pitch.voicedSeconds.toFixed(1)}초</td><td>{b.pitch.voicedSeconds.toFixed(1)}초</td></tr>
        </tbody>
      </table>
      <p class="difference">{medianDifferenceText(a.pitch.median, b.pitch.median)}</p>
      <p class="note">
        범위는 아래 10%~위 10%, 높낮이 폭은 그 범위를 반음으로 센 값이에요 (클수록 억양의 오르내림이 커요). 목표 범위 안은 각 녹음을 남길
        때의 목표 범위로 쟀어요.
      </p>
    </section>

    <section class="card">
      <h3>높이 분포</h3>
      {#if player.loading.length > 0}
        <p class="secondary" role="status">녹음을 읽는 중…</p>
      {:else if player.a !== null && player.b !== null}
        <CompareChart voicedA={player.a.voiced} voicedB={player.b.voiced} target={settings.target} />
      {/if}
      {#each player.failed as side (side)}
        <p class="warning">{side}의 소리 파일을 읽지 못했어요. 위의 숫자만 비교할 수 있어요.</p>
      {/each}
      <p class="note">
        목소리가 잡힌 시간 중 각 높이(반음 반 칸 간격)에 머문 비율이에요. 가로축은 반음 눈금이라 낮은 목소리와 높은 목소리의 흔들림을 같은
        기준으로 볼 수 있어요. 점선은 각 녹음의 중앙값, 파란 띠는 지금 목표 범위예요.
      </p>
    </section>

    <section class="card">
      <h3>듣기</h3>
      {#each ['A', 'B'] as const as side (side)}
        {@const loaded = player.get(side)}
        <button class="listen {side.toLowerCase()}" onclick={() => toggle(side)} disabled={!canPlay || loaded === null}>
          <span>{player.playing === side ? '■' : '▶'} {side} 듣기</span>
          <span class="secondary">{loaded === null ? '' : PitchSummary.durationLabel(loaded.duration)}</span>
        </button>
      {/each}
      <button onclick={() => player.playBoth()} disabled={!canPlay || player.a === null || player.b === null}>A → B 이어 듣기</button>
      {#if player.playing !== null}
        <p class="playing" role="status">
          <span class="side {player.playing.toLowerCase()}"><span class="dot"></span>{player.playing} 듣는 중</span>
          <span class="secondary">{GraphWindow.timeLabel(remaining)}</span>
          <button class="plain small" onclick={() => player.stop()}>멈추기</button>
        </p>
      {/if}
      <p class="note">
        {canPlay
          ? '두 녹음 모두 가장 큰 소리를 같은 크기로 맞춰 들려줘요. 그래서 음량 차이는 비교되지 않아요.'
          : '연습을 멈춘 뒤에 들을 수 있어요.'}
      </p>
    </section>
  {/if}
</div>

<style>
  .compare {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .back {
    align-self: flex-start;
  }
  h2 {
    margin: 0;
    font-size: 1.15rem;
  }
  h3 {
    margin: 0;
    font-size: 0.9rem;
  }
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 14px 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 0.85rem;
  }
  .card p {
    margin: 0;
  }
  .pick {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .pick select {
    flex: 1;
    min-width: 0;
    font: inherit;
    color: var(--text);
    background: var(--fill);
    border: none;
    border-radius: 8px;
    padding: 6px 8px;
  }
  .side {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-weight: 600;
  }
  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
  }
  .side.a .dot {
    background: var(--reference);
  }
  .side.b .dot {
    background: var(--record);
  }
  table {
    border-collapse: collapse;
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }
  th,
  td {
    text-align: left;
    vertical-align: top;
    padding: 4px 6px 4px 0;
  }
  tbody th {
    color: var(--secondary);
    font-weight: 400;
    white-space: nowrap;
  }
  .difference {
    font-size: 0.9rem;
  }
  .listen {
    display: flex;
    justify-content: space-between;
    border-radius: 10px;
  }
  .listen.a {
    color: var(--reference);
  }
  .listen.b {
    color: var(--record);
  }
  .playing {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .playing .secondary {
    flex: 1;
    font-variant-numeric: tabular-nums;
  }
  .secondary {
    color: var(--secondary);
  }
  .warning {
    color: var(--warning);
  }
  .note {
    color: var(--secondary);
    font-size: 0.75rem;
  }
</style>
