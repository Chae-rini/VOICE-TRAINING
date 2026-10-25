import { describe, expect, it } from 'vitest'
import { describeProcessing, MEASUREMENT_CONSTRAINTS, processingNotice } from '../src/audio/processing'

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
