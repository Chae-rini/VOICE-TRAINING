import { isNativeApp } from '../platform/app'
import { resolveParticles } from '../text/korean'

/**
 * 브라우저가 마이크 소리에 거는 자동 처리. 분석하려면 모두 꺼야 한다 (iOS의 `.measurement` 모드와 같은 목적):
 * 자동 음량 조절은 dBFS를 바꾸고, 잡음 제거·에코 제거는 목소리 모양(배음·포먼트)을 바꿀 수 있다.
 * 끄라고 요청해도 브라우저가 못 끌 수 있어서, 실제로 꺼졌는지 확인해 화면에 알린다.
 */

/** 꺼 달라고 요청하는 설정 (`getUserMedia`의 audio 조건). 꼭 지켜야 하는 조건이 아니라, 못 꺼도 마이크는 켜진다. */
export const MEASUREMENT_CONSTRAINTS: MediaTrackConstraints = {
  autoGainControl: false,
  noiseSuppression: false,
  echoCancellation: false,
  channelCount: 1,
}

export type ProcessingState = 'off' | 'on' | 'unknown'

export interface ProcessingItem {
  readonly name: string
  readonly state: ProcessingState
}

const ITEMS: readonly { key: 'autoGainControl' | 'noiseSuppression' | 'echoCancellation'; name: string }[] = [
  { key: 'autoGainControl', name: '자동 음량 조절' },
  { key: 'noiseSuppression', name: '잡음 제거' },
  { key: 'echoCancellation', name: '에코 제거' },
]

/** 마이크 트랙의 실제 설정(`getSettings()`)에서 자동 처리가 꺼졌는지 읽는다. 브라우저가 알려 주지 않으면 'unknown'. */
export function describeProcessing(settings: MediaTrackSettings): ProcessingItem[] {
  return ITEMS.map(({ key, name }) => {
    const value = settings[key]
    return { name, state: value === false ? 'off' : value === true ? 'on' : 'unknown' }
  })
}

/** 화면에 띄울 안내 한 줄. 모두 꺼졌으면 null. 안드로이드 앱에서는 ‘브라우저’ 대신 ‘휴대폰’이라고 쓴다 */
export function processingNotice(items: readonly ProcessingItem[], isApp = isNativeApp()): string | null {
  const device = isApp ? '휴대폰' : '브라우저'
  const on = items.filter((item) => item.state === 'on').map((item) => item.name)
  if (on.length > 0) {
    // 을/를은 마지막 이름의 받침으로 고른다 (자동 음량 조절을, 에코 제거를)
    return resolveParticles(`이 ${device}은(는) ${on.join('·')}을(를) 끄지 못했어요. 음량(dBFS)과 높이·공명 값이 조금 달라질 수 있어요.`)
  }
  if (items.some((item) => item.state === 'unknown')) {
    return resolveParticles(`${device}이(가) 마이크 설정을 알려 주지 않아, 자동 처리가 꺼졌는지 확인하지 못했어요.`)
  }
  return null
}
