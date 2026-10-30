// 대본 본문은 iOS 앱과 같은 파일을 쓴다 (한 곳만 고치면 둘 다 바뀐다).
import scriptsJson from '../../../VoicePractice/Models/PracticeScripts.json'

/** 낭독 연습 대본 한 편 (iOS `Models/PracticeScript.swift`) */
export interface PracticeScript {
  readonly id: string
  /** 대화문, 독백, 수필, 감성 내레이션, 소설, 산문시, 비문학, 음색 교정, 발표, 면접 답변, 전화·안내, 뉴스·일기예보, 동화 낭독 */
  readonly category: string
  /** 비문학의 분야: 과학, 인문, 사회, 예술, 생활 */
  readonly topic?: string
  /** 해요체, 합쇼체, 반말, 문어체 */
  readonly style: string
  readonly title: string
  readonly text: string
  /** 음색 교정 대본이 집중하는 모음 */
  readonly focusVowel?: string
  /** 아직 사람이 사실 관계를 확인하지 않은 비문학 글 */
  readonly needsFactCheck?: boolean
}

export const PRACTICE_SCRIPTS: readonly PracticeScript[] = scriptsJson as PracticeScript[]

/** 소리 내어 읽는 속도 가정 [음절/s]. 실제 낭독 시간과 비교해 나중에 보정할 수 있다. */
export const SYLLABLES_PER_SECOND = 4.5

/**
 * 소리 내어 읽는 음절 수 어림 (iOS `syllableCount`): 한글 음절 + 아라비아 숫자 한 자에 한 음절 (공백·문장부호 제외).
 * 숫자는 2026-10-31부터 대본에 쓴다 ("3시" → 세 시, "18도" → 십팔 도). 한 자에 한 음절은 어림이다.
 */
export function syllableCount(text: string): number {
  let count = 0
  for (const character of text) {
    const code = character.codePointAt(0)!
    if ((code >= 0xac00 && code <= 0xd7a3) || (character >= '0' && character <= '9')) count++
  }
  return count
}

/** 예상 낭독 시간 [s] */
export function estimatedSeconds(script: PracticeScript): number {
  return syllableCount(script.text) / SYLLABLES_PER_SECOND
}

/** 대본을 예상 길이로 거르는 기준 (화면 글자는 iOS와 같다) */
export const SCRIPT_LENGTHS = [
  { id: 'any', label: '전체 길이' },
  { id: 'short', label: '짧게 (20초까지)' },
  { id: 'medium', label: '보통 (20~40초)' },
  { id: 'long', label: '길게 (40초 넘게)' },
] as const
export type ScriptLength = (typeof SCRIPT_LENGTHS)[number]['id']

export function lengthContains(length: ScriptLength, seconds: number): boolean {
  switch (length) {
    case 'any':
      return true
    case 'short':
      return seconds <= 20
    case 'medium':
      return seconds > 20 && seconds <= 40
    case 'long':
      return seconds > 40
  }
}

export const ANY_CATEGORY = '전체'

/** 파일에 처음 나오는 순서대로의 종류 목록 */
export function scriptCategories(scripts: readonly PracticeScript[] = PRACTICE_SCRIPTS): string[] {
  return [...new Set(scripts.map((script) => script.category))]
}

export function filterScripts(
  category: string,
  length: ScriptLength,
  scripts: readonly PracticeScript[] = PRACTICE_SCRIPTS,
): PracticeScript[] {
  return scripts.filter(
    (script) => (category === ANY_CATEGORY || script.category === category) && lengthContains(length, estimatedSeconds(script)),
  )
}

/**
 * [높이] 대본 화면의 섞인 순서 (iOS `ScriptOrder`, 2026-10-31~. 그 전에는 늘 1번 대본부터 파일 순서대로였다).
 * 0..<count를 섞은 자리 목록 (피셔–예이츠). 열 때마다 다른 대본부터 보이고, 이전·다음은 이 순서대로 넘어간다.
 * `random`: 0 이상 1 미만의 수를 주는 함수 (시험에서는 시드를 고정한 것을 넘긴다)
 */
export function shuffledOrder(count: number, random: () => number = Math.random): number[] {
  const order = Array.from({ length: count }, (_, i) => i)
  for (let i = count - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    const swap = order[i]
    order[i] = order[j]
    order[j] = swap
  }
  return order
}

/** 예: "비문학·과학 · 해요체 · 약 24초" */
export function scriptDetails(script: PracticeScript): string {
  const kind = [script.category, script.topic].filter((part) => part !== undefined).join('·')
  return `${kind} · ${script.style} · 약 ${Math.round(estimatedSeconds(script))}초`
}
