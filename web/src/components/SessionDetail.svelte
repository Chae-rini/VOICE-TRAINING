<script lang="ts">
  import { PitchSummary } from '../dsp/pitchSummary'
  import { totalLabel } from '../model/history'
  import { languageLabel, type SessionRecord } from '../model/records'
  import { sessionFeedbackRequest, sessionSummaryOf, takeNumbersLine, takeOwnTarget } from '../practice/sessionLog'
  import { copyText, shareText } from '../practice/sharing'
  import { store } from '../storage/recordStore.svelte'
  import { formatDayTime, formatFullDateTime } from '../text/dates'

  /**
   * 연습 기록 하나 (iOS `PracticeSessionDetailView`): 연습 전체와 녹음마다의 숫자, AI에게 보낼 요약 글.
   * 소리는 남지 않으므로 글만 보낸다. 보낼 앱은 사용자가 브라우저 공유 창에서 고른다 (원칙 2).
   */
  let { record, onBack }: { record: SessionRecord; onBack: () => void } = $props()

  const summary = $derived(sessionSummaryOf(record))
  const request = $derived(sessionFeedbackRequest(summary))
  let didCopy = $state(false)
  let message: string | null = $state(null)

  async function share() {
    const result = await shareText(request)
    message =
      result === 'copied'
        ? '이 브라우저에는 공유 창이 없어서 요약을 복사했어요. 원하는 AI 앱에 붙여 넣으세요.'
        : result === 'failed'
          ? '보내지 못했어요. ‘요약 복사’를 눌러 붙여 넣어 주세요.'
          : null
  }

  async function copy() {
    didCopy = await copyText(request)
    message = didCopy ? null : '복사하지 못했어요. 브라우저가 붙여 넣기 권한을 막았을 수 있어요.'
  }

  async function remove() {
    if (!confirm('이 연습 기록을 지울까요?\n연습 전체와 녹음마다의 숫자가 기록에서 지워져요. 되돌릴 수 없어요.')) return
    const result = await store.removeRecord('sessions', record.id)
    if (result === 'failed') message = store.errorMessage ?? '지우지 못했어요.'
    else onBack()
  }
</script>

<div class="detail">
  <button class="plain back" onclick={onBack}>‹ 기록</button>
  <h2>{formatDayTime(summary.startedAt)}</h2>

  <section class="card">
    <div class="line"><span>연습한 때</span><span>{formatFullDateTime(summary.startedAt)}</span></div>
    <div class="line"><span>연습 시간</span><span>{totalLabel(summary.pitch.duration)}</span></div>
    <div class="line"><span>녹음</span><span>{summary.takeCount}번</span></div>
    <div class="line"><span>말한 언어</span><span>{languageLabel(summary.language)}</span></div>
  </section>

  <section class="card">
    <h3>연습 전체 높이</h3>
    <div class="line"><span>중앙</span><span>{Math.round(summary.pitch.median)} Hz</span></div>
    <div class="line">
      <span>범위 (아래 10%~위 10%)</span><span>{Math.round(summary.pitch.p10)}–{Math.round(summary.pitch.p90)} Hz</span>
    </div>
    <div class="line"><span>목소리가 잡힌 시간</span><span>{PitchSummary.durationLabel(summary.pitch.voicedSeconds)}</span></div>
    {#if summary.pitch.target !== null}
      <div class="line">
        <span>정지한 때 목표 범위</span>
        <span>{Math.trunc(summary.pitch.target.lower)}–{Math.trunc(summary.pitch.target.upper)} Hz</span>
      </div>
      <div class="line">
        <span>목표 범위 안</span>
        <span>{summary.pitch.inTargetFraction === null ? '–' : `${Math.round(summary.pitch.inTargetFraction * 100)}%`}</span>
      </div>
    {:else}
      <div class="line"><span>정지한 때 목표 범위</span><span>정하지 않음</span></div>
    {/if}
  </section>

  <section class="card">
    <h3>녹음마다</h3>
    {#if summary.takes.length === 0}
      <p class="secondary">이 연습에는 녹음마다 기록이 없어요.</p>
    {:else}
      {#each summary.takes as take (take.round)}
        {@const own = takeOwnTarget(take, summary.pitch.target)}
        <div class="take">
          <div class="line"><strong>{take.round}번째 녹음</strong><span>{PitchSummary.durationLabel(take.pitch.duration)}</span></div>
          <span class="numbers">{takeNumbersLine(take)}</span>
          {#if own !== null}
            <span class="secondary small">그때 목표 {Math.trunc(own.lower)}–{Math.trunc(own.upper)} Hz</span>
          {/if}
        </div>
      {/each}
    {/if}
    <p class="note">
      ‘지금 들어보기’를 누르거나 녹음 중에 정지할 때마다 하나씩 남아요. 목소리가 잡히지 않은 녹음은 빠져요. 목표 범위 안 비율은 그 녹음을
      마친 때의 목표 범위로 쟀어요.
    </p>
  </section>

  <section class="card">
    <div class="buttons">
      <button class="fill" onclick={share}>⇪ AI에게 피드백 받기</button>
      <button onclick={copy}>{didCopy ? '✓ 복사했어요' : '요약 복사'}</button>
    </div>
    <p class="note">
      연습 전체와 녹음마다의 숫자를 요약 글로 보내요. 소리는 남지 않아 함께 보낼 수 없어요. 보낸 내용은 고른 앱으로 전송돼요.
    </p>
  </section>

  {#if message !== null}
    <p class="warning" role="status">{message}</p>
  {/if}

  <button class="danger" onclick={remove}>이 연습 기록 지우기</button>
</div>

<style>
  .detail {
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
    font-size: 0.9rem;
  }
  .card p {
    margin: 0;
  }
  .line {
    display: flex;
    justify-content: space-between;
    gap: 12px;
  }
  .line > span:first-child {
    color: var(--secondary);
  }
  .line > span:last-child {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .take {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--divider);
  }
  .take strong {
    font-size: 0.9rem;
  }
  .numbers {
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
  }
  .secondary {
    color: var(--secondary);
  }
  .small {
    font-size: 0.75rem;
  }
  .note {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .buttons {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }
  .fill {
    background: var(--target);
    color: #ffffff;
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
