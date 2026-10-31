import { describe, expect, it } from 'vitest'
import { PRACTICE_SCRIPTS, syllableCount } from '../src/data/scripts'
import {
  DEFAULT_REQUEST,
  isImported,
  isMyScript,
  MAXIMUM_DRAFTS,
  MAXIMUM_TEXT_LENGTH,
  myScriptIdOf,
  myScriptsFrom,
  parseScripts,
  practiceScriptOf,
  scriptRequestPrompt,
} from '../src/model/scriptImport'

// AI 앱에서 쓴 대본 가져오기 (2026-10-31, 사용자 요청).
// iOS VoicePracticeTests/ScriptImportTests.swift와 같은 입력으로 같은 결과를 기대한다 (한쪽을 고치면 다른 쪽도 고친다).

describe('붙여넣은 글 나누기', () => {
  it('‘제목:’ 줄과 ‘---’ 줄로 여러 편을 나누고, 첫 제목 앞의 인사말은 버린다', () => {
    const pasted = [
      '네, 요청하신 대본 두 편을 써 드릴게요!',
      '',
      '제목: 새벽 첫차',
      '오늘은 첫차를 탔어요. 창밖이 아직 깜깜했지요.',
      '---',
      '**제목:** 우산 빌려주기',
      '비가 와서 우산을 빌려줬어요.',
      '',
      '다음 날 돌려받았어요.',
    ].join('\n')
    expect(parseScripts(pasted)).toEqual([
      { title: '새벽 첫차', text: '오늘은 첫차를 탔어요. 창밖이 아직 깜깜했지요.' },
      { title: '우산 빌려주기', text: '비가 와서 우산을 빌려줬어요.\n\n다음 날 돌려받았어요.' },
    ])
  })

  it('여러 모양의 나눔 줄·제목 줄·윈도 줄바꿈, 빈 조각은 건너뛴다', () => {
    const pasted = '## 제목： 하나\r\n본문: 첫째 글이에요.\r\n***\r\n\r\n———\r\nTitle: 둘\r\n둘째 글이에요.\r\n====\r\n'
    expect(parseScripts(pasted)).toEqual([
      { title: '하나', text: '첫째 글이에요.' },
      { title: '둘', text: '둘째 글이에요.' },
    ])
    // 하이픈 두 개나 다른 기호가 섞인 줄은 나눔 줄이 아니다
    expect(parseScripts('제목: 셋\n가 -- 나\n-=-\n다')).toHaveLength(1)
    expect(parseScripts('  \n---\n\n')).toEqual([])
  })

  it('제목이 없으면 첫 문장으로 짓고, 길면 20자에서 자른다', () => {
    expect(parseScripts('짧은 첫 문장. 그다음 문장.')[0]?.title).toBe('짧은 첫 문장')
    // 20자에서 자른 뒤 끝의 빈칸은 떼고 말줄임표를 붙인다
    expect(parseScripts('아주 길고 길어서 제목으로 쓰기에는 너무 긴 첫 문장이에요. 끝.')[0]?.title).toBe('아주 길고 길어서 제목으로 쓰기에는…')
  })

  it('한 번에 20편까지, 한 편은 3000자까지', () => {
    const many = Array.from({ length: 25 }, (_, i) => `제목: ${i + 1}번\n본문 ${i + 1}`).join('\n---\n')
    expect(parseScripts(many)).toHaveLength(MAXIMUM_DRAFTS)
    const huge = parseScripts(`제목: 긴 글\n${'가'.repeat(5000)}`)
    expect(huge[0]?.text).toHaveLength(MAXIMUM_TEXT_LENGTH)
  })
})

describe('AI에게 보낼 부탁 글', () => {
  it('편 수·길이·말투·주제를 넣고, 울림 대본 규칙과 나누기 쉬운 형식을 부탁한다', () => {
    const text = scriptRequestPrompt({ count: 2, seconds: 20, style: '합쇼체', topic: '발표 연습' })
    for (const expected of [
      '한국어 대본을 2편',
      '약 20초 (한글 약 90자)',
      '말투: 합쇼체로',
      '주제: 발표 연습',
      '성별이 드러나는 말',
      '목에 무리가 가는 장면',
      '제목: (제목)\n(본문)\n---',
      '인사말이나 설명 없이',
    ]) {
      expect(text).toContain(expected)
    }
    const free = scriptRequestPrompt(DEFAULT_REQUEST)
    expect(free).toContain('3편')
    expect(free).toContain('자유롭게 섞어서')
    expect(free).toContain('일상에서 있을 법한 장면')
    // 부탁 글의 형식대로 쓴 답은 그대로 나뉜다
    expect(parseScripts('제목: 하나\n첫째.\n---\n제목: 둘\n둘째.').map((d) => d.title)).toEqual(['하나', '둘'])
  })

  it('iOS와 글자 하나까지 같다 (기본 조건)', () => {
    expect(scriptRequestPrompt(DEFAULT_REQUEST)).toBe(
      '[울림 · 낭독 대본 부탁]\n' +
        '보이스 트레이닝 앱 ‘울림’에서 소리 내어 읽으며 목소리를 연습할 한국어 대본을 3편 써 주세요.\n' +
        '\n' +
        '- 길이: 한 편을 소리 내어 읽으면 약 40초 (한글 약 180자)\n' +
        '- 말투: 해요체·합쇼체·반말 등을 자유롭게 섞어서\n' +
        '- 주제: 일상에서 있을 법한 장면으로 자유롭게\n' +
        '- 성별이 드러나는 말(엄마, 언니, 남자, 그녀 등)은 쓰지 말아 주세요.\n' +
        '- 소리를 지르거나 목에 무리가 가는 장면, 무거운 주제는 빼 주세요.\n' +
        '- 실제 사람이나 회사 이름은 쓰지 말아 주세요.\n' +
        '\n' +
        '형식 (그대로 지켜 주세요):\n' +
        '제목: (제목)\n' +
        '(본문)\n' +
        '---\n' +
        '제목: (제목)\n' +
        '(본문)\n' +
        '\n' +
        '인사말이나 설명 없이 대본만 써 주세요.',
    )
  })
})

describe('내 대본', () => {
  it('붙여넣은 순서대로 남기고, 대본 화면에서는 ‘내 대본’ 종류, 말투 없음', () => {
    let n = 0
    const saved = myScriptsFrom(
      [
        { title: '하나', text: '첫째 글이에요.' },
        { title: ' 둘 ', text: '둘째 글' },
      ],
      new Date('2026-10-31T12:00:00.000Z'),
      () => `id-${++n}`,
    )
    expect(saved).toEqual([
      { id: 'id-1', title: '하나', text: '첫째 글이에요.', addedAt: '2026-10-31T12:00:00.000Z' },
      { id: 'id-2', title: '둘', text: '둘째 글', addedAt: '2026-10-31T12:00:00.001Z' },
    ])
    expect(saved.every(isMyScript)).toBe(true)

    const script = practiceScriptOf(saved[0])
    expect(script.category).toBe('내 대본')
    expect(script.style).toBe('')
    expect(isImported(script)).toBe(true)
    expect(myScriptIdOf(script)).toBe('id-1')
    expect(PRACTICE_SCRIPTS.some(isImported)).toBe(false)
    expect(syllableCount(script.text)).toBe(6)
  })

  it('모양이 맞지 않는 항목은 내 대본으로 보지 않는다', () => {
    expect(isMyScript({ id: 'a', title: '', text: '본문', addedAt: '2026-10-31T12:00:00Z' })).toBe(false)
    expect(isMyScript({ id: 'a', title: '제목', text: '  ', addedAt: '2026-10-31T12:00:00Z' })).toBe(false)
    expect(isMyScript({ title: '제목', text: '본문', addedAt: '2026-10-31T12:00:00Z' })).toBe(false)
    expect(isMyScript(null)).toBe(false)
  })
})
