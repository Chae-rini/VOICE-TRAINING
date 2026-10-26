<script lang="ts">
  import { GraphWindow } from '../dsp/graphWindow'
  import type { PhraseEndingAnalysis, PhraseEndType } from '../dsp/phraseEnding'
  import {
    dropText,
    PHRASE_END_TYPE_LABELS,
    phraseDetailLines,
    phraseGuidance,
    phraseHeadline,
    phraseNotes,
    phrasePitchLine,
  } from '../text/phraseEnding'

  /**
   * 요약 카드 안의 구절별 문장 끝 (iOS `PhraseEndingSection`): 요약 한 줄, 숫자 몇 줄, 안내 문구, 펼치면 구절 목록.
   * 색에만 기대지 않게 화살표와 이름을 같이 쓴다.
   */
  let { analysis, takeStart }: { analysis: PhraseEndingAnalysis; takeStart: number } = $props()

  /** 끝이 움직인 방향의 화살표 (iOS `PhraseEndType.symbolName`) */
  const ARROWS: Record<PhraseEndType, string> = { rise: '↗', stable: '→', falling: '↘', dropping: '↓' }

  const details = $derived(phraseDetailLines(analysis))
</script>

<div class="phrases">
  <p class="headline">{phraseHeadline(analysis)}</p>
  {#each details as line (line)}
    <p class="detail">{line}</p>
  {/each}

  {#if analysis.phrases.length > 0}
    <p class="guidance">{phraseGuidance(analysis)}</p>
    <details>
      <summary>구절별로 보기 ({analysis.phrases.length}개)</summary>
      <p class="legend">구절 중앙값 → 끝 {analysis.rules.endWindowSeconds}초 중앙값</p>
      <ol>
        {#each analysis.phrases as phrase, index}
          <li class="row">
            <span class="arrow {phrase.endType}" aria-hidden="true">{ARROWS[phrase.endType]}</span>
            <div class="body">
              <div class="line">
                <span class="name">{index + 1}. {PHRASE_END_TYPE_LABELS[phrase.endType]}</span>
                <span class="pitch">{phrasePitchLine(phrase)}</span>
              </div>
              <span class="sub">
                {[GraphWindow.timeLabel(phrase.startTime - takeStart), dropText(phrase.endDropSemitones), ...phraseNotes(phrase)].join(' · ')}
              </span>
            </div>
          </li>
        {/each}
      </ol>
    </details>
  {/if}
</div>

<style>
  .phrases {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding-top: 10px;
    border-top: 1px solid var(--divider);
  }
  p {
    margin: 0;
  }
  .headline {
    font-weight: 600;
    font-size: 0.9rem;
  }
  .detail {
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .guidance {
    font-size: 0.75rem;
  }
  summary {
    color: var(--target);
    font-size: 0.9rem;
    cursor: pointer;
    padding: 4px 0;
  }
  .legend {
    color: var(--secondary);
    font-size: 0.7rem;
    margin: 4px 0 6px;
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .row {
    display: flex;
    gap: 8px;
    align-items: baseline;
  }
  /* 종류별 색: 안정은 회색, 올라감은 청록, 내려감은 연한 주황, 크게 내려감은 주황 (iOS `PhraseEndType.color`) */
  .arrow {
    min-width: 20px;
    font-weight: 700;
    text-align: center;
  }
  .arrow.rise {
    color: var(--ending-rise);
  }
  .arrow.stable {
    color: var(--inactive);
  }
  .arrow.falling {
    color: var(--warning);
    opacity: 0.6;
  }
  .arrow.dropping {
    color: var(--warning);
  }
  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .line {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    column-gap: 8px;
  }
  .name {
    font-weight: 500;
    font-size: 0.9rem;
  }
  .pitch {
    font-size: 0.9rem;
    font-variant-numeric: tabular-nums;
  }
  .sub {
    color: var(--secondary);
    font-size: 0.75rem;
  }
</style>
