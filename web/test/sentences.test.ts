import { describe, expect, it } from 'vitest'
import practiceSentencesSwift from '../../VoicePractice/Models/PracticeSentences.swift?raw'
import sentencePatternsSwift from '../../VoicePractice/Models/SentencePatterns.swift?raw'
import {
  ANY_CATEGORY,
  estimatedSeconds,
  filterScripts,
  PRACTICE_SCRIPTS,
  scriptCategories,
  scriptDetails,
} from '../src/data/scripts'
import { PRACTICE_SENTENCES, SENTENCE_PATTERNS, SENTENCE_WORDS } from '../src/data/sentences'
import {
  finalConsonantIndex,
  KOREAN_VOWELS,
  mostFrequentVowels,
  PARTICLE_MARKERS,
  resolveParticles,
  vowelCounts,
  vowelSummary,
} from '../src/text/korean'
import { SentenceGenerator, SPEECH_LEVELS } from '../src/text/sentenceGenerator'
import { SplitMix64 } from './signals'

/** Swift 소스의 `static let <name>: … = [ … ]` 배열에서 문자열만 꺼낸다 */
function swiftStringArray(source: string, name: string): string[] {
  const start = source.indexOf(`static let ${name}`)
  const body = source.slice(source.indexOf('[', start), source.indexOf('\n    ]', start))
  return [...body.matchAll(/^\s+"((?:[^"\\]|\\.)*)",\s*$/gm)].map((match) => match[1])
}

describe('iOS와 같은 문장 데이터', () => {
  it('직접 쓴 문장·패턴·단어 목록이 iOS 파일과 같다 (한쪽만 고치면 여기서 알려 준다)', () => {
    expect(PRACTICE_SENTENCES).toEqual(swiftStringArray(practiceSentencesSwift, 'all'))
    expect(SENTENCE_PATTERNS).toEqual(swiftStringArray(sentencePatternsSwift, 'patterns'))

    const words = Object.fromEntries(
      [...sentencePatternsSwift.matchAll(/^\s+"([^"]+)": \[([^\]]*)\],$/gm)].map((match) => [
        match[1],
        [...match[2].matchAll(/"([^"]*)"/g)].map((word) => word[1]),
      ]),
    )
    expect(SENTENCE_WORDS).toEqual(words)
  })
})

// iOS VoicePracticeTests/SentenceGeneratorTests.swift·KoreanVowelTests를 옮겼다.
describe('한글 규칙', () => {
  it.each([
    ['친구을(를)', '친구를'],
    ['동생을(를)', '동생을'],
    ['은행이(가)', '은행이'],
    ['버스이(가)', '버스가'],
    ['우유은(는)', '우유는'],
    ['공원은(는)', '공원은'],
    ['책과(와)', '책과'],
    ['우유과(와)', '우유와'],
    ['공원(으)로', '공원으로'],
    ['버스(으)로', '버스로'],
    ['지하철(으)로', '지하철로'], // ㄹ 받침 뒤에는 "로"
    ['들려줄 길이를 30초(으)로 맞추기', '들려줄 길이를 30초로 맞추기'],
    ['들려줄 길이를 1분(으)로 맞추기', '들려줄 길이를 1분으로 맞추기'],
  ])('받침에 따라 조사를 고른다: %s → %s', (input, expected) => {
    expect(resolveParticles(input)).toBe(expected)
  })

  it('ㅐ와 ㅔ는 모두 ‘에’로 센다', () => {
    const counts = vowelCounts('개미 세 마리')
    expect(counts.get('에')).toBe(2)
    expect(counts.get('이')).toBe(2)
    expect(counts.get('아')).toBe(1)
  })

  it('이중모음과 한글이 아닌 글자는 세지 않는다', () => {
    expect(vowelCounts('야 와 의 ABC 123').size).toBe(0)
  })

  it('많이 나온 모음부터, 개수가 같으면 아·어·오·우·으·이·에 순서', () => {
    expect(mostFrequentVowels('오 이 아 이 아').map((e) => `${e.vowel}${e.count}`)).toEqual(['아2', '이2'])
    expect(vowelSummary('오늘 아침에 우유를 마셨어요.')).toMatch(/^많이 나오는 모음 {2}/)
    expect(vowelSummary('ABC')).toBe(' ')
  })
})

describe('SentenceGenerator (자동 생성 문장)', () => {
  const generator = new SentenceGenerator()

  it('모든 패턴에 오타가 없다', () => {
    for (const pattern of generator.patterns) {
      expect(generator.problems(pattern), pattern).toEqual([])
    }
  })

  it('단어 목록: 비어 있지 않고, 한글로 끝나고, 겹치지 않는다', () => {
    for (const [category, words] of Object.entries(generator.words)) {
      expect(words.length, category).toBeGreaterThan(0)
      expect(new Set(words).size, category).toBe(words.length)
      for (const word of words) {
        expect(finalConsonantIndex(Array.from(word).pop()!), `${category} ${word}`).not.toBeNull()
      }
    }
  })

  it.each([
    '{없는카테고리}에 [가요|갑니다|가].',
    '{장소에 [가요|갑니다|가].',
    '{장소}에 [가요|갑니다].',
    '{장소}에 가요.',
    '{장소} (으)로 [가요|갑니다|가].',
  ])('잘못된 패턴은 문제로 알려 준다: %s', (pattern) => {
    expect(generator.problems(pattern).length).toBeGreaterThan(0)
  })

  it('정한 말투의 끝맺음을 쓴다', () => {
    const random = new SplitMix64(1)
    const r = () => random.uniform()
    const pattern = '{장소}(으)로 [가요|갑니다|가].'
    expect(generator.fill(pattern, 'polite', r).endsWith('가요.')).toBe(true)
    expect(generator.fill(pattern, 'formal', r).endsWith('갑니다.')).toBe(true)
    expect(generator.fill(pattern, 'casual', r).endsWith(' 가.')).toBe(true)
  })

  it.each([1, 2, 3, 4, 5])('15문장(시드 %i): 중복 없음, 말투 5:5:5, 표시 기호가 남지 않음, 7개 모음이 모두 나옴', (seed) => {
    const random = new SplitMix64(seed)
    const deck = generator.makeDeck(15, () => random.uniform())
    expect(deck).toHaveLength(15)
    expect(new Set(deck.map((s) => s.text)).size).toBe(15)
    for (const level of SPEECH_LEVELS) {
      expect(deck.filter((s) => s.level === level)).toHaveLength(5)
    }
    const leftovers = ['{', '}', '[', ']', '|', ...PARTICLE_MARKERS]
    for (const sentence of deck) {
      expect(leftovers.some((mark) => sentence.text.includes(mark)), sentence.text).toBe(false)
    }
    const totals = vowelCounts(deck.map((s) => s.text).join(' '))
    expect(KOREAN_VOWELS.every((vowel) => (totals.get(vowel) ?? 0) > 0)).toBe(true)
  })

  it('같은 시드면 같은 문장이 나온다', () => {
    const first = new SplitMix64(42)
    const second = new SplitMix64(42)
    expect(generator.makeDeck(15, () => first.uniform())).toEqual(generator.makeDeck(15, () => second.uniform()))
  })
})

// iOS VoicePracticeTests/PracticeScriptTests.swift를 옮겼다 (같은 JSON 파일을 읽는다).
describe('대본 200편', () => {
  const genderedWords = [
    '엄마', '아빠', '어머니', '아버지', '언니', '오빠', '누나', '고모', '삼촌', '할머니', '할아버지',
    '아저씨', '아주머니', '아줌마', '남편', '아내', '남자', '여자', '그녀', '소년', '소녀', '신랑', '신부',
  ]

  it('200편, 번호·제목·본문이 겹치지 않는다', () => {
    expect(PRACTICE_SCRIPTS).toHaveLength(200)
    expect(new Set(PRACTICE_SCRIPTS.map((s) => s.id)).size).toBe(200)
    expect(new Set(PRACTICE_SCRIPTS.map((s) => s.title)).size).toBe(200)
    expect(new Set(PRACTICE_SCRIPTS.map((s) => s.text)).size).toBe(200)
  })

  it('예상 낭독 시간이 10~60초 안이고, 성별이 드러나는 말과 아라비아 숫자를 쓰지 않는다', () => {
    for (const script of PRACTICE_SCRIPTS) {
      const seconds = estimatedSeconds(script)
      expect(seconds >= 10 && seconds <= 60, `${script.id} ${seconds}초`).toBe(true)
      expect(genderedWords.filter((w) => script.text.includes(w) || script.title.includes(w)), script.id).toEqual([])
      expect(/[0-9]/.test(script.text), script.id).toBe(false)
    }
  })

  it('종류는 파일 순서대로 8가지, 거르기는 종류와 길이를 함께 본다', () => {
    expect(scriptCategories()).toEqual(['대화문', '독백', '수필', '감성 내레이션', '소설', '산문시', '비문학', '음색 교정'])
    expect(filterScripts(ANY_CATEGORY, 'any')).toHaveLength(200)
    const shortTalks = filterScripts('대화문', 'short')
    expect(shortTalks.every((s) => s.category === '대화문' && estimatedSeconds(s) <= 20)).toBe(true)
    const lengths = (['short', 'medium', 'long'] as const).map((l) => filterScripts(ANY_CATEGORY, l).length)
    expect(lengths.reduce((a, b) => a + b, 0)).toBe(200) // 길이 구간이 겹치거나 빠지지 않는다
  })

  it('대본 설명 한 줄: 종류(분야) · 말투 · 약 n초', () => {
    expect(scriptDetails(PRACTICE_SCRIPTS[0])).toMatch(/^대화문 · 해요체 · 약 \d+초$/)
    const nonfiction = PRACTICE_SCRIPTS.find((s) => s.topic !== undefined)!
    expect(scriptDetails(nonfiction)).toContain(`비문학·${nonfiction.topic}`)
  })
})
