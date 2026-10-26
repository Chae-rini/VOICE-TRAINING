import type { CapacitorConfig } from '@capacitor/cli'

/**
 * 울림 안드로이드 앱(APK) 설정 (Docs/WEB_PLAN.md ‘APK 계획’).
 * 웹 빌드 결과(dist/)를 앱 안에 넣어 폰 안에서 https://localhost로 연다. https라 마이크가 켜지고, 인터넷이 필요 없다.
 * 원격 주소(server.url)는 쓰지 않는다 (원칙 2: 앱은 네트워크를 쓰지 않는다).
 * 앱 ID는 설치한 뒤에 바꿀 수 없고, 실명이 들어가지 않게 GitHub 이름으로 정했다.
 */
const config: CapacitorConfig = {
  appId: 'io.github.chae_rini.ullim',
  appName: '울림',
  webDir: 'dist',
}

export default config
