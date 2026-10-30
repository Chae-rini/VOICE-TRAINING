import { PRACTICE_SCRIPTS, type PracticeScript } from '../data/scripts'
import { PRACTICE_SENTENCES } from '../data/sentences'

/**
 * ‘내 목소리 재기’에서 읽을 글 (iOS `Models/BaselineReading.swift`, 2026-10-31~. 그 전에는 늘 같은 문장 하나였다).
 * 내 문장과, 평소 말투에 가까운 대본(대화문·독백·비문학·수필) 중에서 재기 창을 열 때마다 무작위로 고른다.
 * 소설·산문시·감성 내레이션·음색 교정 대본은 연기하는 목소리나 특정 모음 연습으로 기울기 쉬워 ‘평소 목소리’ 재기에는 쓰지 않는다.
 * 사실 확인 전인 비문학 대본도 빼고, 확인이 끝나면(`needsFactCheck`가 없어지면) 저절로 들어간다.
 * 공명 밝기(F2)는 읽은 모음에 따라 달라지므로, 글이 바뀌면 잴 때마다 기준 F2도 조금 흔들릴 수 있다 (화면에 알린다).
 */
export interface BaselineReading {
  readonly text: string
  /** 대본이면 제목, 내 문장이면 null */
  readonly title: string | null
}

/** 재기에 쓰는 대본 종류 */
export const BASELINE_SCRIPT_CATEGORIES: ReadonlySet<string> = new Set(['대화문', '독백', '비문학', '수필'])

/** 후보가 하나도 없을 때 (대본 파일을 못 읽고 내 문장도 비었을 때) */
export const BASELINE_FALLBACK: BaselineReading = { text: '회의는 오후 두 시에 시작합니다.', title: null }

/** 10초 안에 두세 번 읽을 수 있는 짧은 문장인가 (내 문장). 대본은 처음부터 읽다가 10초가 지나면 끝난다 */
export function isSentence(reading: BaselineReading): boolean {
  return reading.title === null
}

export function readingInstruction(reading: BaselineReading): string {
  return isSentence(reading)
    ? '10초 동안 이 문장을 평소처럼 두세 번 읽어 주세요.'
    : '10초 동안 이 대본을 처음부터 평소처럼 읽어 주세요. 다 못 읽어도 괜찮아요.'
}

/** 고를 수 있는 글: 내 문장 전부 + 재기에 쓰는 종류이면서 사실 확인이 끝난 대본 */
export function baselineCandidates(
  sentences: readonly string[] = PRACTICE_SENTENCES,
  scripts: readonly PracticeScript[] = PRACTICE_SCRIPTS,
): BaselineReading[] {
  return [
    ...sentences.map((text) => ({ text, title: null })),
    ...scripts
      .filter((script) => BASELINE_SCRIPT_CATEGORIES.has(script.category) && script.needsFactCheck !== true)
      .map((script) => ({ text: script.text, title: script.title })),
  ]
}

function sameReading(a: BaselineReading, b: BaselineReading | null): boolean {
  return b !== null && a.text === b.text && a.title === b.title
}

/**
 * 무작위로 하나. 바로 앞에 보인 글(`previous`)은 다시 고르지 않는다 (후보가 그것 하나뿐이면 그대로).
 * `random`: 0 이상 1 미만의 수를 주는 함수 (시험에서는 시드를 고정한 것을 넘긴다)
 */
export function randomBaselineReading(
  previous: BaselineReading | null = null,
  candidates: readonly BaselineReading[] = baselineCandidates(),
  random: () => number = Math.random,
): BaselineReading {
  const others = candidates.filter((reading) => !sameReading(reading, previous))
  const pool = others.length === 0 ? candidates : others
  return pool[Math.floor(random() * pool.length)] ?? BASELINE_FALLBACK
}
