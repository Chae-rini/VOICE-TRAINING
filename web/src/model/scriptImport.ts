import { SYLLABLES_PER_SECOND, type PracticeScript } from '../data/scripts'

/**
 * AI 앱에서 쓴 대본을 울림으로 가져오기 (iOS `Models/ScriptImport.swift`, 2026-10-31~). 앱은 인터넷에 연결하지 않으므로(원칙 2)
 * ① 울림이 부탁 글을 만들면 사용자가 고른 AI 앱으로 보내고(공유 창·복사) ② AI가 쓴 답을 사용자가 복사해 와 붙여넣는다.
 * 붙여넣은 글은 ‘제목:’ 줄과 ‘---’ 줄로 나눠 대본 여러 편으로 만든다 (부탁 글이 이 형식을 부탁한다).
 * 나누는 규칙·부탁 글은 iOS와 같다 (한쪽을 고치면 다른 쪽도 고친다. 두 시험이 같은 결과를 기대한다).
 */

/** 붙여넣은 글에서 나온 대본 한 편 (저장 전, 미리 보기에서 제목을 고칠 수 있다) */
export interface ScriptDraft {
  title: string
  text: string
}

/** 한 번에 가져오는 최대 편 수 */
export const MAXIMUM_DRAFTS = 20
/** [글자] 한 편 본문의 최대 길이. 넘으면 자른다 (실수로 아주 긴 글을 붙여넣었을 때) */
export const MAXIMUM_TEXT_LENGTH = 3000
/** [글자] 제목이 없어 첫 문장으로 지을 때의 최대 길이 */
export const FALLBACK_TITLE_LENGTH = 20

// 글자 수는 코드 포인트로 센다 (iOS는 글자 묶음으로 센다. 한글은 같고, 이모지가 섞이면 조금 다를 수 있다)
const length = (text: string) => [...text].length
const prefix = (text: string, count: number) => [...text].slice(0, count).join('')

/** iOS `trimmingCharacters(in: .whitespaces)`: 줄바꿈이 아닌 빈칸(탭·공백 문자)만 뗀다 */
function trimSpaces(text: string): string {
  return text.replace(/^[\t\p{Zs}]+|[\t\p{Zs}]+$/gu, '')
}

/**
 * 붙여넣은 글을 대본들로 나눈다.
 * - ‘---’처럼 같은 기호(-, —, =, *, _)만 세 개 넘게 있는 줄에서 나눈다.
 * - ‘제목:’ 줄(앞의 #·** 같은 꾸밈은 무시)이 있으면 제목으로 쓰고, 그 앞의 줄(“네, 대본을 써 드릴게요” 같은 인사)은 버린다.
 * - 제목이 없으면 본문의 첫 문장으로 제목을 짓는다. 본문 맨 앞의 ‘본문:’은 뗀다.
 */
export function parseScripts(pasted: string): ScriptDraft[] {
  const lines = pasted.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')
  const chunks: string[][] = [[]]
  for (const line of lines) {
    if (isSeparator(line)) chunks.push([])
    else chunks[chunks.length - 1].push(line)
  }
  return chunks
    .map(draftFrom)
    .filter((draft) => draft !== null)
    .slice(0, MAXIMUM_DRAFTS)
}

function isSeparator(line: string): boolean {
  const trimmed = trimSpaces(line)
  const first = trimmed[0]
  if (length(trimmed) < 3 || first === undefined || !'-—=*_'.includes(first)) return false
  return [...trimmed].every((character) => character === first)
}

/** 줄 앞뒤의 마크다운 꾸밈(#, **, __)을 뗀다 */
function plain(line: string): string {
  let text = trimSpaces(line)
  while (text.startsWith('#')) text = text.slice(1)
  text = text.replaceAll('**', '').replaceAll('__', '')
  return trimSpaces(text)
}

/** "제목: 이웃의 인사" → "이웃의 인사". 제목 줄이 아니면 null */
function titleValue(line: string): string | null {
  const text = plain(line)
  for (const label of ['제목', 'title', 'Title']) {
    if (!text.startsWith(label)) continue
    const rest = trimSpaces(text.slice(label.length))
    if (rest[0] !== ':' && rest[0] !== '：') continue
    const value = trimSpaces(rest.slice(1))
    return value === '' ? null : value
  }
  return null
}

function draftFrom(chunk: string[]): ScriptDraft | null {
  let lines = chunk
  let title: string | null = null
  const titleIndex = lines.findIndex((line) => titleValue(line) !== null)
  if (titleIndex >= 0) {
    title = titleValue(lines[titleIndex])
    lines = lines.slice(titleIndex + 1) // 제목 앞의 인사말까지 버린다
  }
  let body = lines.map(plain).join('\n')
  // 빈 줄이 여러 개면 하나로
  while (body.includes('\n\n\n')) body = body.replaceAll('\n\n\n', '\n\n')
  body = body.trim()
  for (const label of ['본문:', '본문 :']) {
    if (body.startsWith(label)) body = body.slice(label.length).trim()
  }
  if (body === '') return null
  if (length(body) > MAXIMUM_TEXT_LENGTH) body = prefix(body, MAXIMUM_TEXT_LENGTH)
  return { title: title ?? fallbackTitle(body), text: body }
}

/** 첫 문장(마침표·물음표·느낌표·줄바꿈까지)을 20자까지 */
function fallbackTitle(body: string): string {
  const end = [...body].findIndex((character) => '.?!。\n'.includes(character))
  const title = trimSpaces(end < 0 ? body : prefix(body, end))
  if (length(title) <= FALLBACK_TITLE_LENGTH) return title
  return `${trimSpaces(prefix(title, FALLBACK_TITLE_LENGTH))}…`
}

// MARK: - AI에게 보낼 부탁 글

/** 부탁 글에 넣는 조건. 고른 대로 글이 바뀐다 */
export interface ScriptRequest {
  /** 편 수 (1~5) */
  count: number
  /** [s] 한 편을 소리 내어 읽는 시간 (20·40·60) */
  seconds: number
  /** null이면 말투를 섞어서 */
  style: string | null
  /** 비우면 일상에서 있을 법한 장면으로 */
  topic: string
}

export const DEFAULT_REQUEST: ScriptRequest = { count: 3, seconds: 40, style: null, topic: '' }
export const COUNT_RANGE = { min: 1, max: 5 } as const
export const SECONDS_OPTIONS = [20, 40, 60] as const
export const STYLE_OPTIONS = ['해요체', '합쇼체', '반말', '문어체'] as const

/**
 * AI 앱에 보낼 부탁 글. 울림 대본과 같은 규칙(성별이 드러나는 말 쓰지 않기, 목에 무리 가는 장면 빼기)을 부탁하고,
 * 붙여넣을 때 나누기 쉬운 형식(‘제목:’ 줄, ‘---’ 줄)을 정해 준다.
 */
export function scriptRequestPrompt(request: ScriptRequest): string {
  const syllables = Math.round(request.seconds * SYLLABLES_PER_SECOND)
  const style = request.style === null ? '해요체·합쇼체·반말 등을 자유롭게 섞어서' : `${request.style}로`
  const topic = request.topic.trim()
  return [
    '[울림 · 낭독 대본 부탁]',
    `보이스 트레이닝 앱 ‘울림’에서 소리 내어 읽으며 목소리를 연습할 한국어 대본을 ${request.count}편 써 주세요.`,
    '',
    `- 길이: 한 편을 소리 내어 읽으면 약 ${request.seconds}초 (한글 약 ${syllables}자)`,
    `- 말투: ${style}`,
    `- 주제: ${topic === '' ? '일상에서 있을 법한 장면으로 자유롭게' : topic}`,
    '- 성별이 드러나는 말(엄마, 언니, 남자, 그녀 등)은 쓰지 말아 주세요.',
    '- 소리를 지르거나 목에 무리가 가는 장면, 무거운 주제는 빼 주세요.',
    '- 실제 사람이나 회사 이름은 쓰지 말아 주세요.',
    '',
    '형식 (그대로 지켜 주세요):',
    '제목: (제목)',
    '(본문)',
    '---',
    '제목: (제목)',
    '(본문)',
    '',
    '인사말이나 설명 없이 대본만 써 주세요.',
  ].join('\n')
}

// MARK: - 내 대본

/**
 * 가져와 남긴 내 대본 (iOS `ImportedScript`). 기록 폴더의 `울림-대본.json`에 둔다 (`storage/archive.ts`).
 * [높이] 대본 화면에 ‘내 대본’ 종류로 보인다. ‘모든 기록 지우기’로는 지우지 않는다 (연습 기록이 아니라 내가 모은 대본이라서).
 */
export interface MyScript {
  readonly id: string
  readonly title: string
  readonly text: string
  /** ISO 시각 */
  readonly addedAt: string
}

/** 대본 화면의 종류 이름 */
export const MY_SCRIPT_CATEGORY = '내 대본'
/** 대본 화면에서 쓰는 번호의 머리 (앱에 든 대본 s001~과 겹치지 않게) */
export const MY_SCRIPT_ID_PREFIX = 'my-'

export function isMyScript(value: unknown): value is MyScript {
  const script = value as Partial<MyScript> | null
  return (
    typeof script?.id === 'string' &&
    typeof script.title === 'string' &&
    script.title.trim() !== '' &&
    typeof script.text === 'string' &&
    script.text.trim() !== '' &&
    typeof script.addedAt === 'string'
  )
}

/** 미리 보기에서 고른 대본들을 남길 모양으로. 붙여넣은 순서가 보이게 더한 시각을 1 ms씩 늦춘다 (iOS와 같음) */
export function myScriptsFrom(drafts: readonly ScriptDraft[], addedAt: Date, newId: () => string): MyScript[] {
  return drafts.map((draft, offset) => ({
    id: newId(),
    title: draft.title.trim(),
    text: draft.text,
    addedAt: new Date(addedAt.getTime() + offset).toISOString(),
  }))
}

/** 내 대본을 대본 화면에서 쓰는 모양으로 (말투는 알 수 없어 비워 둔다) */
export function practiceScriptOf(script: MyScript): PracticeScript {
  return {
    id: MY_SCRIPT_ID_PREFIX + script.id,
    category: MY_SCRIPT_CATEGORY,
    style: '',
    title: script.title,
    text: script.text,
  }
}

export function isImported(script: PracticeScript): boolean {
  return script.id.startsWith(MY_SCRIPT_ID_PREFIX)
}

/** 대본 화면의 번호 → 내 대본의 id */
export function myScriptIdOf(script: PracticeScript): string | null {
  return isImported(script) ? script.id.slice(MY_SCRIPT_ID_PREFIX.length) : null
}
