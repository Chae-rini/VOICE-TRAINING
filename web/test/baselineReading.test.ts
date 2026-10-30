import { describe, expect, it } from 'vitest'
import type { PracticeScript } from '../src/data/scripts'
import { PRACTICE_SENTENCES } from '../src/data/sentences'
import {
  BASELINE_FALLBACK,
  baselineCandidates,
  isSentence,
  randomBaselineReading,
  readingInstruction,
  type BaselineReading,
} from '../src/model/baselineReading'
import { SplitMix64 } from './signals'

// ‘내 목소리 재기’에서 읽을 글을 무작위로 고르기 (2026-10-31, 그 전에는 늘 같은 문장 하나).
// iOS VoicePracticeTests/BaselineReadingTests.swift와 같은 확인이다 (한쪽을 고치면 다른 쪽도 고친다).

function script(id: string, category: string, needsFactCheck?: boolean): PracticeScript {
  return { id, category, style: '해요체', title: `제목 ${id}`, text: `본문 ${id}`, needsFactCheck }
}

/** 시드를 고정한 0~1 난수 */
function seeded(seed: number): () => number {
  const generator = new SplitMix64(seed)
  return () => generator.uniform()
}

describe('내 목소리 재기에서 읽을 글', () => {
  it('후보: 내 문장 전부 + 평소 말투에 가까운 대본(대화문·독백·비문학·수필) 중 사실 확인이 끝난 것', () => {
    const scripts = [
      script('a', '대화문'),
      script('b', '독백'),
      script('c', '수필'),
      script('d', '비문학'),
      script('e', '비문학', true),
      script('f', '소설'),
      script('g', '산문시'),
      script('h', '감성 내레이션'),
      script('i', '음색 교정'),
    ]
    const candidates = baselineCandidates(['문장 하나', '문장 둘'], scripts)
    expect(candidates.map((c) => c.text)).toEqual(['문장 하나', '문장 둘', '본문 a', '본문 b', '본문 c', '본문 d'])
    expect(candidates.filter(isSentence)).toHaveLength(2)
    expect(candidates.at(-1)?.title).toBe('제목 d')

    // 앱에 든 글: 내 문장 15개 + 대화문 50·독백 30·수필 20 (비문학 40편은 아직 모두 사실 확인 전,
    // 2026-10-31에 더한 발표·면접 답변 등은 ‘평소 목소리’ 재기와 맞지 않아 넣지 않음)
    const bundled = baselineCandidates()
    expect(bundled).toHaveLength(PRACTICE_SENTENCES.length + 100)
    expect(bundled).toContainEqual({ text: '회의는 오후 두 시에 시작합니다.', title: null })
  })

  it('무작위로 고르되 바로 앞에 보인 글은 다시 고르지 않는다. 같은 시드면 같은 글', () => {
    const candidates = baselineCandidates()
    const random = seeded(42)
    let previous: BaselineReading = randomBaselineReading(null, candidates, random)
    const seen = new Set([previous.text])
    for (let i = 0; i < 200; i++) {
      const next = randomBaselineReading(previous, candidates, random)
      expect(next).not.toEqual(previous)
      seen.add(next.text)
      previous = next
    }
    expect(seen.size, '여러 글이 고루 나와야 한다').toBeGreaterThan(50)

    expect(randomBaselineReading(null, candidates, seeded(7))).toEqual(randomBaselineReading(null, candidates, seeded(7)))
  })

  it('후보가 하나뿐이면 그것을, 하나도 없으면 예전 문장을 쓴다', () => {
    const only: BaselineReading = { text: '하나', title: null }
    expect(randomBaselineReading(only, [only], seeded(1))).toEqual(only)
    expect(randomBaselineReading(null, [], seeded(1))).toEqual(BASELINE_FALLBACK)
  })

  it('안내 글: 문장은 두세 번, 대본은 처음부터 (다 못 읽어도 괜찮다)', () => {
    expect(readingInstruction({ text: '짧은 문장', title: null })).toBe('10초 동안 이 문장을 평소처럼 두세 번 읽어 주세요.')
    expect(readingInstruction({ text: '긴 대본', title: '제목' })).toBe(
      '10초 동안 이 대본을 처음부터 평소처럼 읽어 주세요. 다 못 읽어도 괜찮아요.',
    )
  })
})
