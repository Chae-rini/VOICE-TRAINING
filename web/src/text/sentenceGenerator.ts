import { SENTENCE_PATTERNS, SENTENCE_WORDS } from '../data/sentences'
import { KOREAN_VOWELS, PARTICLE_MARKERS, resolveParticles, vowelCounts, type KoreanVowel } from './korean'

/** 말투. 패턴의 `[해요체|합쇼체|반말]` 중 몇 번째를 쓸지 정한다. */
export const SPEECH_LEVELS = ['polite', 'formal', 'casual'] as const // 해요체, 합쇼체, 반말
export type SpeechLevel = (typeof SPEECH_LEVELS)[number]

export interface GeneratedSentence {
  readonly text: string
  readonly level: SpeechLevel
}

/** 0 ≤ 값 < 1 을 돌려주는 난수 (Math.random, 테스트에서는 시드 고정 난수) */
export type Random = () => number

type Token = { kind: 'text'; text: string } | { kind: 'slot'; category: string } | { kind: 'choice'; options: string[] }

function pick<T>(items: readonly T[], random: Random): T | undefined {
  return items.length === 0 ? undefined : items[Math.floor(random() * items.length)]
}

function shuffled<T>(items: readonly T[], random: Random): T[] {
  const result = [...items]
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[result[i], result[j]] = [result[j], result[i]]
  }
  return result
}

/**
 * 패턴을 단어로 채워 연습 문장을 만든다 (iOS `Models/SentenceGenerator.swift`). 모두 기기 안에서 규칙대로 만든다.
 * 난수가 달라 iOS와 같은 문장이 나오지는 않지만, 규칙(중복 없음·말투 고르게·모음 균형)은 같다.
 */
export class SentenceGenerator {
  /** 문장 한 자리에 후보를 몇 개 만들어 보고 그중 모음 균형이 가장 좋은 것을 고를지. */
  private readonly candidatesPerSentence = 12

  constructor(
    readonly patterns: readonly string[] = SENTENCE_PATTERNS,
    readonly words: Readonly<Record<string, readonly string[]>> = SENTENCE_WORDS,
  ) {}

  /**
   * `count`개 문장을 만든다.
   * - 같은 문장은 넣지 않고, 패턴을 다 쓰기 전에는 같은 패턴을 다시 쓰지 않는다.
   * - 해요체·합쇼체·반말을 돌아가며 배정해 고르게 섞는다.
   * - 자리마다 후보 여러 개 중 7개 단모음이 가장 고르게 쌓이는 문장을 고른다.
   */
  makeDeck(count = 15, random: Random = Math.random): GeneratedSentence[] {
    const levels = shuffled(
      Array.from({ length: count }, (_, i) => SPEECH_LEVELS[i % SPEECH_LEVELS.length]),
      random,
    )
    const deck: GeneratedSentence[] = []
    const vowelTotals = new Map<KoreanVowel, number>()
    let unusedPatterns: string[] = []

    for (const level of levels) {
      if (unusedPatterns.length === 0) unusedPatterns = [...this.patterns]

      let best: { text: string; patternIndex: number; score: number } | null = null
      for (let attempt = 0; attempt < this.candidatesPerSentence; attempt++) {
        if (unusedPatterns.length === 0) break
        const patternIndex = Math.floor(random() * unusedPatterns.length)
        const text = this.fill(unusedPatterns[patternIndex], level, random)
        if (deck.some((sentence) => sentence.text === text)) continue

        const totals = new Map(vowelTotals)
        for (const [vowel, n] of vowelCounts(text)) totals.set(vowel, (totals.get(vowel) ?? 0) + n)
        const score = SentenceGenerator.vowelImbalance(totals)
        if (best !== null && best.score <= score) continue
        best = { text, patternIndex, score }
      }

      if (best === null) continue
      deck.push({ text: best.text, level })
      for (const [vowel, n] of vowelCounts(best.text)) vowelTotals.set(vowel, (vowelTotals.get(vowel) ?? 0) + n)
      unusedPatterns.splice(best.patternIndex, 1)
    }
    return deck
  }

  /** 패턴 하나를 정해진 말투로 채운다. */
  fill(pattern: string, level: SpeechLevel, random: Random = Math.random): string {
    let text = ''
    const usedWords = new Set<string>() // 한 문장 안에서 같은 단어가 두 번 나오지 않게
    const levelIndex = SPEECH_LEVELS.indexOf(level)
    for (const token of SentenceGenerator.tokenize(pattern).tokens) {
      switch (token.kind) {
        case 'text':
          text += token.text
          break
        case 'slot': {
          const choices = (this.words[token.category] ?? []).filter((word) => !usedWords.has(word))
          const word = pick(choices, random) ?? token.category
          usedWords.add(word)
          text += word
          break
        }
        case 'choice':
          text += token.options[levelIndex] ?? token.options[0] ?? ''
          break
      }
    }
    return resolveParticles(text)
  }

  /** 패턴의 오타를 찾는다. 문제가 없으면 빈 배열. */
  problems(pattern: string): string[] {
    const { tokens, problems } = SentenceGenerator.tokenize(pattern)
    let hasChoice = false
    for (const token of tokens) {
      if (token.kind === 'slot' && (this.words[token.category] ?? []).length === 0) {
        problems.push(`없는 카테고리 {${token.category}}`)
      }
      if (token.kind === 'choice') {
        hasChoice = true
        if (token.options.length !== SPEECH_LEVELS.length) {
          problems.push(`[ ] 안에는 해요체|합쇼체|반말 세 가지를 적어야 해요: [${token.options.join('|')}]`)
        }
        if (token.options.some((option) => option.includes('{'))) {
          problems.push('[ ] 안에는 {카테고리}를 쓸 수 없어요')
        }
      }
    }
    if (!hasChoice) problems.push('말투를 고르는 [해요체|합쇼체|반말]이 없어요')
    const marker = PARTICLE_MARKERS.find((m) => pattern.includes(' ' + m))
    if (marker !== undefined) problems.push(`조사 표시 ${marker}는 앞 단어에 붙여 써야 해요`)
    return problems
  }

  /** 7개 단모음 개수가 얼마나 들쭉날쭉한지 (변동계수 = 표준편차 ÷ 평균). 0이면 완전히 고르다. */
  static vowelImbalance(counts: ReadonlyMap<KoreanVowel, number>): number {
    const values = KOREAN_VOWELS.map((vowel) => counts.get(vowel) ?? 0)
    const mean = values.reduce((a, b) => a + b, 0) / values.length
    if (!(mean > 0)) return Number.POSITIVE_INFINITY
    const variance = values.reduce((sum, v) => sum + (v - mean) * (v - mean), 0) / values.length
    return Math.sqrt(variance) / mean
  }

  /** 패턴을 글자 조각, {카테고리}, [말투 선택]으로 나눈다. 괄호 짝이 안 맞으면 문제로 알린다. */
  private static tokenize(pattern: string): { tokens: Token[]; problems: string[] } {
    const tokens: Token[] = []
    const problems: string[] = []
    let rest = pattern
    while (rest.length > 0) {
      const first = rest[0]
      if (first === '{' || first === '[') {
        const closing = first === '{' ? '}' : ']'
        const end = rest.indexOf(closing)
        if (end === -1) {
          problems.push(`'${first}'의 짝 '${closing}'가 없어요`)
          tokens.push({ kind: 'text', text: rest })
          return { tokens, problems }
        }
        const inside = rest.slice(1, end)
        tokens.push(first === '{' ? { kind: 'slot', category: inside } : { kind: 'choice', options: inside.split('|') })
        rest = rest.slice(end + 1)
      } else if (first === '}' || first === ']') {
        problems.push(`짝이 없는 '${first}'`)
        rest = rest.slice(1)
      } else {
        const match = rest.search(/[{[\]}]/)
        const end = match === -1 ? rest.length : match
        tokens.push({ kind: 'text', text: rest.slice(0, end) })
        rest = rest.slice(end)
      }
    }
    return { tokens, problems }
  }
}
