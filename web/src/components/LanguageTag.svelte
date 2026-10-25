<script lang="ts">
  import { markerPath } from '../graph/historyChart'
  import { languageLabel, type PracticeLanguage } from '../model/records'

  /** 언어 표시: 그래프 점과 같은 모양(분홍) + 언어 이름. `plain`이면 바탕 없이 (범례용) */
  let { language, plain = false }: { language: PracticeLanguage; plain?: boolean } = $props()
</script>

<span class="tag" class:plain>
  <svg viewBox="0 0 10 10" aria-hidden="true"><path d={markerPath(language, 5, 5, 3.4)} /></svg>
  {languageLabel(language)}
</span>

<style>
  .tag {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 1px 7px;
    border-radius: 999px;
    background: var(--fill);
    color: var(--secondary);
    font-size: 0.7rem;
    font-weight: 500;
    white-space: nowrap;
  }
  .tag.plain {
    background: none;
    padding: 0;
    font-size: 0.75rem;
  }
  svg {
    width: 9px;
    height: 9px;
    fill: var(--voice);
  }
</style>
