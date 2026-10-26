import { App } from '@capacitor/app'
import { navigation } from '../components/navigation.svelte'
import { session } from '../practice/session.svelte'
import { closeOpenDialog, runBackHandlers } from './backButton'

/**
 * 안드로이드 앱을 ‘웹사이트’가 아니라 휴대폰 앱처럼 동작하게 한다 (앱에서만 부른다, 2026-10-26 1묶음).
 * - 뒤로 버튼: 열린 창 → 열린 메뉴·자세히 화면 → [높이] 탭으로 → [높이]에서는 앱을 뒤로 보낸다 (안드로이드 기본 동작과 같게, 연습 상태는 그대로)
 * - 다른 앱으로 가거나 전화가 와서 화면이 가려지면 연습을 멈춘다 (iOS의 오디오 끊김 처리와 같게, 녹음 중이면 거기까지 남긴다).
 *   공유 창처럼 앱 위에 반쯤 뜨는 창은 화면이 가려진 것이 아니라 멈추지 않는다
 * - 길게 눌러 글자 선택·확대·누를 때 깜빡임 같은 웹 동작은 `html.app` 스타일(app.css)과 확대 막기로 없앤다.
 *   글자 크기는 휴대폰의 글꼴 크기 설정을 따른다 (MainActivity가 웹뷰에 알려 준다)
 */
export function installNativeApp(): void {
  document.documentElement.classList.add('app')
  const viewport = document.querySelector('meta[name="viewport"]')
  viewport?.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover, maximum-scale=1, user-scalable=no')

  void App.addListener('backButton', () => {
    if (closeOpenDialog() || runBackHandlers()) return
    if (navigation.tab !== 'pitch') {
      navigation.tab = 'pitch'
      return
    }
    void App.minimizeApp()
  })

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden' && session.isRunning) void session.stop()
  })
}
