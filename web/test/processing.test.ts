import { describe, expect, it } from 'vitest'
import { MicError } from '../src/audio/micInput'
import { describeProcessing, MEASUREMENT_CONSTRAINTS, processingNotice } from '../src/audio/processing'
import { parseFailureMessage } from '../src/storage/archive'

describe('마이크 자동 처리 끄기', () => {
  it('자동 음량 조절·잡음 제거·에코 제거를 꺼 달라고 요청한다 (못 꺼도 마이크는 켜지는 조건)', () => {
    expect(MEASUREMENT_CONSTRAINTS).toMatchObject({ autoGainControl: false, noiseSuppression: false, echoCancellation: false })
    // 꼭 지켜야 하는 조건(exact)이면 못 끄는 브라우저에서 마이크 자체가 안 켜진다
    expect(JSON.stringify(MEASUREMENT_CONSTRAINTS)).not.toContain('exact')
  })

  it('모두 꺼졌으면 안내가 없다', () => {
    const items = describeProcessing({ autoGainControl: false, noiseSuppression: false, echoCancellation: false })
    expect(items.map((item) => item.state)).toEqual(['off', 'off', 'off'])
    expect(processingNotice(items)).toBeNull()
  })

  it('브라우저가 끄지 못한 것은 이름을 대고 알린다', () => {
    const items = describeProcessing({ autoGainControl: true, noiseSuppression: false, echoCancellation: true })
    expect(processingNotice(items)).toBe(
      '이 브라우저는 자동 음량 조절·에코 제거를 끄지 못했어요. 음량(dBFS)과 높이·공명 값이 조금 달라질 수 있어요.',
    )
    expect(processingNotice(describeProcessing({ autoGainControl: true, noiseSuppression: false, echoCancellation: false }))).toContain(
      '자동 음량 조절을 끄지',
    )
  })

  it('설정을 알려 주지 않는 브라우저는 확인하지 못했다고 알린다', () => {
    const items = describeProcessing({ echoCancellation: false })
    expect(items.map((item) => item.state)).toEqual(['unknown', 'unknown', 'off'])
    expect(processingNotice(items)).toContain('확인하지 못했어요')
  })
})

// 1묶음 ‘웹 티 없애기’: 안드로이드 앱에서는 ‘브라우저·페이지·새로 고침’ 대신 휴대폰·앱 말로 안내한다 (웹 문구는 그대로)
describe('앱에서 보이는 안내 문구', () => {
  it('마이크 자동 처리 안내는 ‘휴대폰’이라고 쓴다', () => {
    const items = describeProcessing({ autoGainControl: true, noiseSuppression: false, echoCancellation: true })
    expect(processingNotice(items, true)).toBe(
      '이 휴대폰은 자동 음량 조절·에코 제거를 끄지 못했어요. 음량(dBFS)과 높이·공명 값이 조금 달라질 수 있어요.',
    )
    expect(processingNotice(describeProcessing({ echoCancellation: false }), true)).toBe(
      '휴대폰이 마이크 설정을 알려 주지 않아, 자동 처리가 꺼졌는지 확인하지 못했어요.',
    )
    expect(processingNotice(describeProcessing({ echoCancellation: false }), false)).toBe(
      '브라우저가 마이크 설정을 알려 주지 않아, 자동 처리가 꺼졌는지 확인하지 못했어요.',
    )
  })

  it('마이크 오류는 앱 설정으로 안내하고, 앱 문구가 없는 경우는 웹 문구를 쓴다', () => {
    expect(MicError.message('denied', true)).toContain('설정 › 애플리케이션 › 울림 › 권한')
    expect(MicError.message('other', true)).not.toContain('페이지')
    expect(MicError.message('notFound', true)).toBe(MicError.messages.notFound)
    expect(MicError.message('denied', false)).toBe(MicError.messages.denied)
  })

  it('새 판 파일 안내: 앱이면 새 판 설치, 웹이면 새로 고침', () => {
    expect(parseFailureMessage('울림-기록.json', 'newerVersion', true)).toContain('새 판으로 설치')
    expect(parseFailureMessage('울림-기록.json', 'newerVersion', false)).toContain('새로 고쳐')
  })
})
