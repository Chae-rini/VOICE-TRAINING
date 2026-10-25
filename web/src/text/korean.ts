/**
 * 한글 글자 규칙: 조사 고르기와 단모음 세기 (iOS `SentenceGenerator.swift`의 KoreanParticle, `KoreanVowel.swift`).
 * 한글 음절의 코드 = 0xAC00 + (초성 × 21 + 중성) × 28 + 종성
 */

const FIRST_SYLLABLE = 0xac00 // 가
const LAST_SYLLABLE = 0xd7a3 // 힣

/** 한글 음절의 받침 번호. 0 = 받침 없음, 8 = ㄹ. 한글 음절이 아니면 null. */
export function finalConsonantIndex(character: string): number | null {
  const code = character.codePointAt(0)
  if (code === undefined || code < FIRST_SYLLABLE || code > LAST_SYLLABLE) return null
  return (code - FIRST_SYLLABLE) % 28
}

const PARTICLE_RULES: readonly { marker: string; afterConsonant: string; afterVowel: string }[] = [
  { marker: '을(를)', afterConsonant: '을', afterVowel: '를' },
  { marker: '이(가)', afterConsonant: '이', afterVowel: '가' },
  { marker: '은(는)', afterConsonant: '은', afterVowel: '는' },
  { marker: '과(와)', afterConsonant: '과', afterVowel: '와' },
  { marker: '(으)로', afterConsonant: '으로', afterVowel: '로' },
]

/** 조사 표시: 을(를), 이(가), 은(는), 과(와), (으)로 */
export const PARTICLE_MARKERS: readonly string[] = PARTICLE_RULES.map((rule) => rule.marker)

/** 앞 글자의 받침을 보고 조사를 고른다. 예: 친구을(를) → 친구를, 지하철(으)로 → 지하철로 */
export function resolveParticles(text: string): string {
  let result = text
  for (const rule of PARTICLE_RULES) {
    let at = result.indexOf(rule.marker)
    while (at !== -1) {
      const before = Array.from(result.slice(0, at)).pop()
      const final = before === undefined ? null : finalConsonantIndex(before)
      let particle: string
      if (final === null || final === 0) {
        particle = rule.afterVowel // 받침 없음 (한글이 아니어도 이쪽)
      } else if (final === 8 && rule.marker === '(으)로') {
        particle = rule.afterVowel // ㄹ 받침 뒤의 (으)로는 "로": 지하철로
      } else {
        particle = rule.afterConsonant
      }
      result = result.slice(0, at) + particle + result.slice(at + rule.marker.length)
      at = result.indexOf(rule.marker)
    }
  }
  return result
}

/** 한국어 단모음 7개. 현대 서울말에서는 ㅐ와 ㅔ가 거의 같은 소리라서 하나(에)로 묶는다. 순서도 iOS와 같다. */
export const KOREAN_VOWELS = ['아', '어', '오', '우', '으', '이', '에'] as const
export type KoreanVowel = (typeof KOREAN_VOWELS)[number]

/** 한글 음절 하나의 가운데 소리(중성)가 단모음이면 그 모음, 아니면 null (이중모음·한글이 아닌 글자). */
export function vowelOf(syllable: string): KoreanVowel | null {
  const code = syllable.codePointAt(0)
  if (code === undefined || code < FIRST_SYLLABLE || code > LAST_SYLLABLE) return null
  const medial = Math.floor(((code - FIRST_SYLLABLE) % (21 * 28)) / 28)
  switch (medial) {
    case 0:
      return '아' // ㅏ
    case 4:
      return '어' // ㅓ
    case 8:
      return '오' // ㅗ
    case 13:
      return '우' // ㅜ
    case 18:
      return '으' // ㅡ
    case 20:
      return '이' // ㅣ
    case 1:
    case 5:
      return '에' // ㅐ, ㅔ
    default:
      return null
  }
}

/** 문장에 각 단모음이 몇 번 나오는지 센다. 글자(표기) 기준이라 "같이[가치]"처럼 발음이 바뀌는 경우는 반영하지 않는다. */
export function vowelCounts(text: string): Map<KoreanVowel, number> {
  const counts = new Map<KoreanVowel, number>()
  for (const character of text) {
    const vowel = vowelOf(character)
    if (vowel !== null) counts.set(vowel, (counts.get(vowel) ?? 0) + 1)
  }
  return counts
}

/** 많이 나온 모음부터 최대 `limit`개. 개수가 같으면 아·어·오·우·으·이·에 순서. */
export function mostFrequentVowels(text: string, limit = 2): { vowel: KoreanVowel; count: number }[] {
  const counts = vowelCounts(text)
  return KOREAN_VOWELS.map((vowel) => ({ vowel, count: counts.get(vowel) ?? 0 }))
    .filter((entry) => entry.count > 0)
    .sort((a, b) => b.count - a.count) // 정렬은 안정적이라 개수가 같으면 원래 순서를 지킨다
    .slice(0, limit)
}

/** 예: "많이 나오는 모음  아 3 · 이 2" */
export function vowelSummary(sentence: string): string {
  const top = mostFrequentVowels(sentence)
  if (top.length === 0) return ' '
  return '많이 나오는 모음  ' + top.map((entry) => `${entry.vowel} ${entry.count}`).join(' · ')
}
