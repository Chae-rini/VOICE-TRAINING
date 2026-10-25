<script lang="ts">
  import { PitchSummary } from '../dsp/pitchSummary'
  import { copyText, downloadTake, shareFeedback } from '../practice/sharing'
  import type { RecordedTake } from '../practice/take'

  /**
   * 마지막 녹음(방금 녹음 또는 불러온 파일)의 피치 요약 카드 (iOS `RecordingSummaryView`).
   * "AI에게 피드백 받기"는 요약(원하면 녹음 파일도)을 브라우저 공유 창에 넘기고, 보낼 앱은 사용자가 고른다.
   * "파일로 저장"은 녹음을 WAV로 이 기기에 내려받는다. 앱 자체는 인터넷으로 아무것도 보내지 않는다.
   * (‘기록에 남기기’는 웹에 [기록]이 생기면 더한다.)
   */
  let { take, summary }: { take: RecordedTake; summary: PitchSummary } = $props()

  let isShareMenuOpen = $state(false)
  let message: string | null = $state(null)
  let didCopy = $state(false)

  // 녹음이 바뀌면 안내를 지운다
  $effect(() => {
    void take.id
    didCopy = false
    message = null
  })

  async function share(includesAudio: boolean) {
    isShareMenuOpen = false
    const result = await shareFeedback(take, summary, includesAudio)
    message =
      result === 'copied'
        ? includesAudio
          ? '이 브라우저는 녹음 파일을 함께 넘길 수 없어서 요약만 복사했어요. 원하는 AI 앱에 붙여 넣으세요.'
          : '이 브라우저에는 공유 창이 없어서 요약을 복사했어요. 원하는 AI 앱에 붙여 넣으세요.'
        : result === 'failed'
          ? '보내지 못했어요. ‘요약 복사’를 눌러 붙여 넣어 주세요.'
          : null
  }

  async function copy() {
    didCopy = await copyText(summary.feedbackRequest(take.title, false))
    message = didCopy ? null : '복사하지 못했어요. 브라우저가 붙여 넣기 권한을 막았을 수 있어요.'
  }
</script>

<section class="card" aria-label="마지막 녹음 요약">
  <div class="header">
    <span class="title">{take.title}</span>
    <span class="duration">{PitchSummary.durationLabel(summary.duration)}</span>
  </div>

  <dl class="stats">
    <div><dt>중앙</dt><dd>{Math.round(summary.median)} Hz</dd></div>
    <div><dt>범위</dt><dd>{Math.round(summary.p10)}–{Math.round(summary.p90)} Hz</dd></div>
    <div>
      <dt>목표 범위 안</dt>
      <dd>{summary.inTargetFraction === null ? '–' : `${Math.round(summary.inTargetFraction * 100)}%`}</dd>
    </div>
  </dl>

  <button class="wide" onclick={() => downloadTake(take)}>⤓ 파일로 저장</button>

  <div class="actions">
    <div class="menu">
      <button class="share" onclick={() => (isShareMenuOpen = !isShareMenuOpen)} aria-expanded={isShareMenuOpen}>
        ⇪ AI에게 피드백 받기
      </button>
      {#if isShareMenuOpen}
        <div class="menu-items" role="menu">
          <button role="menuitem" onclick={() => share(false)}>요약 글만 보내기</button>
          <button role="menuitem" onclick={() => share(true)}>녹음 파일과 함께 보내기</button>
        </div>
      {/if}
    </div>
    <button onclick={copy}>{didCopy ? '✓ 복사했어요' : '요약 복사'}</button>
  </div>

  {#if message !== null}
    <p class="message" role="status">{message}</p>
  {/if}

  <p class="caption">
    ‘녹음 파일과 함께’는 파일을 받는 앱만 보여요. 원하는 앱이 없으면 ‘요약 복사’ 후 붙여 넣으세요. 보낸 내용은 고른 앱으로
    전송돼요. ‘파일로 저장’은 WAV 파일을 이 기기에 내려받아요 (브라우저에 따라 저장할 곳을 물어요).
  </p>
</section>

<style>
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .header {
    display: flex;
    justify-content: space-between;
    gap: 8px;
  }
  .title {
    font-weight: 600;
    font-size: 0.95rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .duration {
    color: var(--secondary);
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }
  .stats {
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
    font-size: 0.95rem;
    font-variant-numeric: tabular-nums;
  }
  .wide {
    width: 100%;
  }
  .actions {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }
  .menu {
    position: relative;
  }
  .share {
    background: var(--target);
    color: #ffffff;
  }
  .menu-items {
    position: absolute;
    left: 0;
    top: calc(100% + 6px);
    min-width: 220px;
    padding: 6px;
    border-radius: 12px;
    background: var(--background);
    box-shadow: 0 8px 30px rgb(0 0 0 / 0.25);
    display: flex;
    flex-direction: column;
    z-index: 5;
  }
  .menu-items button {
    background: none;
    color: var(--text);
    text-align: left;
    border-radius: 8px;
  }
  .menu-items button:hover {
    background: var(--fill);
  }
  .message {
    margin: 0;
    color: var(--record);
    font-size: 0.8rem;
  }
  .caption {
    margin: 0;
    color: var(--secondary);
    font-size: 0.7rem;
  }
</style>
