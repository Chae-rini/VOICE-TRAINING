<script lang="ts">
  import { tick } from 'svelte'
  import { PitchSummary } from '../dsp/pitchSummary'
  import { defaultPair } from '../model/comparison'
  import {
    dailyPractice,
    dateDomain,
    filterPoints,
    HISTORY_PERIODS,
    historyTotals,
    periodContains,
    sessionPitchDomain,
    sessionPoint,
    totalLabel,
    type HistoryPeriod,
  } from '../model/history'
  import {
    PRACTICE_LANGUAGES,
    readableRecords,
    recordingDisplayTitle,
    type PracticeLanguage,
  } from '../model/records'
  import { settings } from '../model/settings.svelte'
  import { store } from '../storage/recordStore.svelte'
  import { formatDay, formatDayTime } from '../text/dates'
  import CompareScreen from './CompareScreen.svelte'
  import HistoryCharts from './HistoryCharts.svelte'
  import LanguageTag from './LanguageTag.svelte'
  import RecordingDetail from './RecordingDetail.svelte'
  import SessionDetail from './SessionDetail.svelte'
  import StorageCard from './StorageCard.svelte'

  /**
   * [기록] 화면 (iOS `HistoryScreen`): 기간·언어를 골라 연습의 흐름(그래프)을 보고, 남긴 녹음·연습 기록·내 목소리 재기 이력을 살펴본다.
   * 기록은 내 기록 폴더(또는 기록 파일)에만 있다. 점수·향상률·연속 기록은 보여 주지 않는다.
   * 남긴 녹음·연습 기록을 누르면 자세히 화면으로 바뀐다 (목록은 숨겨 두어 돌아오면 스크롤 위치가 그대로다).
   */
  /** null이면 모든 언어 */
  let language: PracticeLanguage | null = $state(null)
  let detail = $state<
    { kind: 'recording' | 'session'; id: string } | { kind: 'compare'; a: string; b: string } | null
  >(null)
  let message: string | null = $state(null)
  let now = $state(new Date())
  let screen: HTMLDivElement
  /** [px] 자세히 화면을 열 때의 목록 스크롤 위치 (돌아오면 그대로) */
  let listScroll = 0

  const records = $derived(readableRecords(store.records))
  const period = $derived(settings.historyPeriod)
  const isEmpty = $derived(records.sessions.length === 0 && records.recordings.length === 0 && records.baselines.length === 0)
  /** 저장 위치를 먼저 봐야 할 때(폴더를 안 골랐거나 저장 전·오류)는 맨 위에, 아니면 맨 아래에 둔다 */
  const storageFirst = $derived(store.status.kind !== 'connected' || store.unsaved || store.errorMessage !== null)

  const isShown = (date: string, recordLanguage: PracticeLanguage | null = null) =>
    periodContains(period, new Date(date), now) && (language === null || recordLanguage === null || recordLanguage === language)

  const points = $derived(filterPoints(records.sessions.map(sessionPoint), period, language, now))
  const totals = $derived(historyTotals(points))
  const shownRecordings = $derived(records.recordings.filter((r) => isShown(r.recordedAt, r.language)))
  const shownSessions = $derived(records.sessions.filter((s) => isShown(s.startedAt, s.language)).reverse())
  const shownBaselines = $derived(records.baselines.filter((b) => isShown(b.measuredAt)))

  const detailRecording = $derived.by(() => {
    const d = detail
    return d?.kind === 'recording' ? records.recordings.find((r) => r.id === d.id) : undefined
  })
  const detailSession = $derived.by(() => {
    const d = detail
    return d?.kind === 'session' ? records.sessions.find((s) => s.id === d.id) : undefined
  })
  const comparing = $derived(detail?.kind === 'compare' && records.recordings.length >= 2 ? detail : null)
  const showsDetail = $derived(detailRecording !== undefined || detailSession !== undefined || comparing !== null)

  async function show(next: NonNullable<typeof detail>) {
    now = new Date()
    listScroll = screen.scrollTop
    detail = next
    await tick()
    screen.scrollTop = 0
  }

  function open(kind: 'recording' | 'session', id: string) {
    void show({ kind, id })
  }

  /** 지금 보이는 녹음(기간·언어)이 두 개 이상이면 그 안에서, 아니면 전체에서 가장 먼저와 가장 최근을 고른다 */
  function openCompare() {
    const candidates = shownRecordings.length >= 2 ? shownRecordings : records.recordings
    const pair = defaultPair(candidates, (r) => new Date(r.recordedAt))
    if (pair !== null) void show({ kind: 'compare', a: pair.a.id, b: pair.b.id })
  }

  async function back() {
    detail = null
    await tick()
    screen.scrollTop = listScroll
  }

  async function removeBaseline(id: string) {
    if (!confirm('이 기록을 지울까요? 되돌릴 수 없어요.')) return
    const result = await store.removeRecord('baselineHistory', id)
    message = result === 'failed' ? (store.errorMessage ?? '지우지 못했어요.') : null
  }

  async function removeAll() {
    const question =
      '모든 기록을 지울까요?\n연습 기록, 남긴 녹음과 메모, 내 목소리·모음 재기 이력이 모두 지워져요. 지금 쓰는 기준 목소리·목표 범위·모음 지도는 그대로예요. 되돌릴 수 없어요.'
    if (!confirm(question)) return
    const result = await store.removeAllRecords()
    message = result === 'failed' ? (store.errorMessage ?? '지우지 못했어요.') : null
  }
</script>

<div class="screen" bind:this={screen}>
  <!-- 자세히 화면 -->
  {#if detailRecording !== undefined}
    <RecordingDetail record={detailRecording} onBack={back} />
  {:else if detailSession !== undefined}
    <SessionDetail record={detailSession} onBack={back} />
  {:else if comparing !== null}
    <CompareScreen recordings={records.recordings} initialA={comparing.a} initialB={comparing.b} onBack={back} />
  {/if}

  <div class="list" class:hidden={showsDetail}>
    <h1>기록</h1>

    {#if storageFirst}
      <StorageCard />
    {/if}

    {#if isEmpty}
      <section class="card empty">
        <h2>아직 기록이 없어요</h2>
        <p>
          ‘반복 루프 재생’으로 30초 넘게 연습하면 연습 기록이 저절로 남아요. 요약 카드의 ‘기록에 남기기’를 누르면 녹음도 여기에 모여요.
        </p>
      </section>
    {:else}
      <section class="card filters">
        <div class="segments" role="group" aria-label="기간">
          {#each HISTORY_PERIODS as option (option.id)}
            <button
              class:selected={period === option.id}
              aria-pressed={period === option.id}
              onclick={() => {
                now = new Date()
                settings.setHistoryPeriod(option.id as HistoryPeriod)
              }}>{option.label}</button
            >
          {/each}
        </div>
        <label class="line">
          <span>말한 언어</span>
          <select
            value={language ?? ''}
            onchange={(event) => {
              const value = (event.currentTarget as HTMLSelectElement).value
              language = value === '' ? null : (value as PracticeLanguage)
            }}
          >
            <option value="">모든 언어</option>
            {#each PRACTICE_LANGUAGES as option (option.id)}
              <option value={option.id}>{option.label}</option>
            {/each}
          </select>
        </label>
      </section>

      <section class="card">
        <dl class="totals">
          <div><dt>연습</dt><dd>{totals.sessionCount}번</dd></div>
          <div><dt>연습한 날</dt><dd>{totals.dayCount}일</dd></div>
          <div><dt>모두</dt><dd>{totalLabel(totals.practiceSeconds)}</dd></div>
        </dl>
        {#if points.length === 0}
          <p class="secondary">이 기간에 남은 연습 기록이 없어요.</p>
        {:else}
          <HistoryCharts
            {points}
            daily={dailyPractice(points)}
            domain={dateDomain(points, period, now)}
            pitchDomain={sessionPitchDomain(points, settings.target, settings.baseline?.median ?? null)}
            target={settings.target}
            baseline={settings.baseline?.median ?? null}
          />
        {/if}
      </section>

      <section class="card">
        <h2>남긴 녹음</h2>
        {#if shownRecordings.length === 0}
          <p class="secondary">요약 카드의 ‘기록에 남기기’로 남긴 녹음이 여기에 모여요.</p>
        {/if}
        {#if records.recordings.length >= 2}
          <button class="compare" onclick={openCompare}>◫ 두 녹음 나란히 비교</button>
        {/if}
        {#each shownRecordings as recording (recording.id)}
          <button class="row" onclick={() => open('recording', recording.id)}>
            <span class="row-top">
              <strong>{recordingDisplayTitle(recording)}</strong>
              <span class="secondary">{PitchSummary.durationLabel(recording.pitch.duration)}</span>
            </span>
            <span class="row-top">
              <span class="numbers"
                >중앙 {Math.round(recording.pitch.median)} Hz · {Math.round(recording.pitch.p10)}–{Math.round(recording.pitch.p90)} Hz</span
              >
              <LanguageTag language={recording.language} />
            </span>
            {#if recording.memo !== ''}
              <span class="memo">{recording.memo}</span>
            {/if}
          </button>
        {/each}
      </section>

      {#if shownSessions.length > 0}
        <section class="card">
          <h2>연습 기록</h2>
          {#each shownSessions as record (record.id)}
            <button class="row" onclick={() => open('session', record.id)}>
              <span class="row-top">
                <span>{formatDayTime(new Date(record.startedAt))}</span>
                <span class="numbers">중앙 {Math.round(record.pitch.median)} Hz</span>
              </span>
              <span class="row-top">
                <span class="secondary small">연습 {totalLabel(record.pitch.duration)} · 녹음 {record.takeCount}번</span>
                <LanguageTag language={record.language} />
              </span>
            </button>
          {/each}
          <p class="note">
            정지할 때마다 숫자만 저절로 남아요 (소리는 남지 않아요). 누르면 녹음마다의 숫자를 보고 AI에게 보낼 수 있어요.
          </p>
        </section>
      {/if}

      {#if shownBaselines.length > 0}
        <section class="card">
          <h2>내 목소리 재기</h2>
          {#each shownBaselines as baseline (baseline.id)}
            <div class="baseline">
              <span>{formatDay(new Date(baseline.measuredAt))}</span>
              <span class="reference numbers"
                >중앙 {Math.round(baseline.median)} Hz · {Math.round(baseline.low)}–{Math.round(baseline.high)} Hz</span
              >
              <button class="plain small remove" onclick={() => removeBaseline(baseline.id)} aria-label="이 기록 지우기">지우기</button>
            </div>
          {/each}
        </section>
      {/if}
    {/if}

    {#if message !== null}
      <p class="warning" role="alert">{message}</p>
    {/if}

    {#if !storageFirst}
      <StorageCard />
    {/if}

    {#if !isEmpty}
      <button class="danger" onclick={removeAll}>모든 기록 지우기</button>
    {/if}
    <p class="note">기록은 내가 고른 기록 폴더(또는 기록 파일)에만 있어요. 울림은 기록을 어디로도 보내지 않아요.</p>
  </div>
</div>

<style>
  .screen {
    height: 100%;
    overflow-y: auto;
    box-sizing: border-box;
    padding: max(12px, env(safe-area-inset-top)) 16px 24px;
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .list.hidden {
    display: none;
  }
  h1 {
    margin: 4px 0 0;
    font-size: 1.4rem;
  }
  h2 {
    margin: 0;
    font-size: 0.95rem;
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
  .empty p {
    color: var(--secondary);
  }
  .segments {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 2px;
    padding: 2px;
    border-radius: 10px;
    background: var(--fill);
  }
  .segments button {
    border-radius: 8px;
    background: none;
    color: var(--text);
    padding: 6px 0;
  }
  .segments button.selected {
    background: var(--background);
    font-weight: 600;
  }
  .line {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  select {
    font: inherit;
    color: var(--target);
    background: var(--fill);
    border: none;
    border-radius: 8px;
    padding: 4px 8px;
  }
  .totals {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    margin: 0;
  }
  dt {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  dd {
    margin: 2px 0 0;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .row {
    display: flex;
    flex-direction: column;
    gap: 3px;
    width: 100%;
    padding: 10px 0 8px;
    border-radius: 0;
    border-top: 1px solid var(--divider);
    background: none;
    color: var(--text);
    text-align: left;
  }
  .row-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
  }
  .row strong {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .numbers {
    font-variant-numeric: tabular-nums;
  }
  .memo {
    color: var(--secondary);
    font-size: 0.8rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .baseline {
    display: flex;
    align-items: center;
    gap: 8px;
    padding-top: 8px;
    border-top: 1px solid var(--divider);
  }
  .baseline .reference {
    flex: 1;
    text-align: right;
    color: var(--reference);
    font-size: 0.8rem;
  }
  .remove {
    color: #ff3b30;
  }
  .compare {
    align-self: flex-start;
  }
  .secondary {
    color: var(--secondary);
  }
  .small {
    font-size: 0.8rem;
  }
  .note {
    margin: 0;
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .warning {
    margin: 0;
    color: var(--warning);
    font-size: 0.85rem;
  }
  .danger {
    background: color-mix(in srgb, #ff3b30 14%, transparent);
    color: #ff3b30;
    padding: 12px 16px;
  }
</style>
