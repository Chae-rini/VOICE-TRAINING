import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { isNativeApp } from './app'

/**
 * 짧은 진동 (앱에서만, iOS의 `sensoryFeedback`과 같은 때): 녹음 하나가 끝나 듣기로 넘어갈 때 약하게,
 * 오래 연습해 쉬어 가기 안내가 뜰 때 강하게. 진동을 못 하는 기기면 조용히 넘어간다.
 */
export function vibrate(strength: 'light' | 'heavy'): void {
  if (!isNativeApp()) return
  void Haptics.impact({ style: strength === 'light' ? ImpactStyle.Light : ImpactStyle.Heavy }).catch(() => {})
}
