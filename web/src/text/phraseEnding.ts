import type { PhraseEnding, PhraseEndingAnalysis, PhraseEndType } from '../dsp/phraseEnding'

/*
 * 문장 끝 분석을 사람이 읽는 글로 바꾼다 ([높이] 요약 카드, AI 요청문). iOS `Models/PhraseEndingText.swift`와 같은 글이다.
 * 한쪽을 고치면 다른 쪽도 고친다. 판정·점수가 아니라 숫자와 방향만 말하고, 끝이 내려가는 것 자체를 나쁘다고 하지 않는다 (원칙 3).
 * 글 속의 기준 숫자(3반음, 0.3초 등)는 `PhraseEndingRules.json`에서 가져온다.
 */

/** 화면에 쓰는 종류 이름 */
export const PHRASE_END_TYPE_LABELS: Readonly<Record<PhraseEndType, string>> = {
  rise: '올라감',
  stable: '안정',
  falling: '내려감',
  dropping: '크게 내려감',
}

/** 요약 한 줄. 예: "문장 끝 11개 중 7개가 3반음 넘게 내려갔어요" */
export function phraseHeadline(analysis: PhraseEndingAnalysis): string {
  const { summary } = analysis
  const limit = ruleNumber(analysis.rules.stableMaxDropSemitones)
  if (summary.phraseCount === 0) return '문장으로 나눌 만큼 목소리가 이어진 곳이 없어요'
  if (summary.fallingOrDroppingCount === 0) return `문장 끝 ${summary.phraseCount}개 중 ${limit}반음 넘게 내려간 곳은 없어요`
  return `문장 끝 ${summary.phraseCount}개 중 ${summary.fallingOrDroppingCount}개가 ${limit}반음 넘게 내려갔어요`
}

/** 요약 한 줄 아래의 숫자들 (해당할 때만). 구절이 없으면 빈 배열. */
export function phraseDetailLines(analysis: PhraseEndingAnalysis): string[] {
  const { summary, target } = analysis
  if (summary.meanEndDropSemitones === null) return []
  const end = ruleNumber(analysis.rules.endWindowSeconds)
  const lines = [`평균 ${dropText(summary.meanEndDropSemitones)}`]
  if (target !== null && summary.endBelowTargetCount !== null) {
    lines.push(`바닥이 목표 하한(${Math.trunc(target.lower)} Hz) 아래로 내려간 끝: ${summary.endBelowTargetCount}개`)
  }
  if (summary.outOfTargetAtEndFraction !== null && summary.endFrameShare !== null) {
    lines.push(
      `목표 범위 밖 순간의 ${percent(summary.outOfTargetAtEndFraction)}%가 문장 끝 ${end}초에 있어요 (문장 끝은 목소리의 ${percent(summary.endFrameShare)}%)`,
    )
  }
  if (summary.possibleFryCount > 0) {
    lines.push(`끝이 긁혔을 수도 있는 곳: ${summary.possibleFryCount}개 (높이를 잘못 읽었을 수도 있어요)`)
  }
  return lines
}

/** 안내 문구. 끝이 내려가는 건 자연스럽다는 것을 먼저 말한다. */
export function phraseGuidance(analysis: PhraseEndingAnalysis): string {
  return analysis.target === null
    ? `끝이 내려가는 건 자연스러워요. ${ruleNumber(analysis.rules.stableMaxDropSemitones)}반음 안쪽으로만 내려가게 해 보세요.`
    : '끝이 내려가는 건 자연스러워요. 바닥이 목표 하한 아래로 내려가지 않게만 해 보세요.'
}

/** AI 요청문에 넣을 줄들. 구절이 없으면 빈 배열. */
export function phraseRequestLines(analysis: PhraseEndingAnalysis): string[] {
  const { summary, rules } = analysis
  if (summary.meanEndDropSemitones === null || summary.fallingOrDroppingFraction === null) return []
  const silence = ruleNumber(rules.phraseBreakSilenceSeconds)
  const end = ruleNumber(rules.endWindowSeconds)
  const limit = ruleNumber(rules.stableMaxDropSemitones)
  const lines = [
    `문장 끝 (무성음 ${silence}초 이상에서 구절을 나누고, 구절마다 마지막 ${end}초를 구절 전체와 비교)`,
    `- 구절 수: ${summary.phraseCount}개`,
    `- 평균 하강 폭: ${summary.meanEndDropSemitones.toFixed(1)}반음 (구절 중앙값 → 마지막 ${end}초 중앙값, +면 내려감)`,
    `- ${limit}반음 넘게 내려간 구절: ${summary.fallingOrDroppingCount}개 (${percent(summary.fallingOrDroppingFraction)}%)`,
  ]
  if (summary.endBelowTargetCount !== null) {
    lines.push(
      `- 끝 바닥(마지막 ${end}초의 아래 ${percent(rules.endFloorPercentile)}%)이 목표 하한 아래인 구절: ${summary.endBelowTargetCount}개`,
    )
  }
  if (summary.outOfTargetAtEndFraction !== null && summary.endFrameShare !== null) {
    lines.push(
      `- 목표 범위 밖 순간 중 문장 끝 ${end}초에 있던 비율: ${percent(summary.outOfTargetAtEndFraction)}% (문장 끝은 목소리가 잡힌 시간의 ${percent(summary.endFrameShare)}%)`,
    )
  }
  lines.push(`- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): ${summary.possibleFryCount}개`)
  lines.push(
    analysis.target === null
      ? `한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 ${limit}반음 이내인지로 봐 주세요.`
      : `한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 ${limit}반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.`,
  )
  return lines
}

/** 구절 중앙값 → 끝 중앙값. 예: "182 → 158 Hz" */
export function phrasePitchLine(phrase: PhraseEnding): string {
  return `${Math.round(phrase.phraseMedian)} → ${Math.round(phrase.endMedian)} Hz`
}

/** 눈여겨볼 점 (해당할 때만). 예: ["바닥 150 Hz · 목표 하한 아래", "긁혔을 수도 있어요"] */
export function phraseNotes(phrase: PhraseEnding): string[] {
  const notes: string[] = []
  if (phrase.endBelowTarget === true) notes.push(`바닥 ${Math.round(phrase.endFloor)} Hz · 목표 하한 아래`)
  if (phrase.possibleFry) notes.push('긁혔을 수도 있어요')
  return notes
}

/** 예: 2.4 → "2.4반음 내려감", −1.2 → "1.2반음 올라감", 0.02 → "거의 그대로" */
export function dropText(drop: number): string {
  const size = Math.abs(drop).toFixed(1)
  if (size === '0.0') return '거의 그대로'
  return drop > 0 ? `${size}반음 내려감` : `${size}반음 올라감`
}

/** 0~1 → 반올림한 백분율 */
function percent(fraction: number): number {
  return Math.round(fraction * 100)
}

/** 기준값을 글에 넣을 때: 3 → "3", 0.25 → "0.25" */
function ruleNumber(value: number): string {
  return String(value)
}
