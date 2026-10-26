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
  // 디버그 빌드는 앱 기능을 부를 때마다 주고받은 값을 로그에 찍는데, 녹음 파일 내용(base64)까지 통째로 남는다 (A2 확인).
  // 개인 녹음이 로그에 남지 않게, 그리고 큰 녹음에서 느려지지 않게 끈다. 앱 안 화면은 adb + DevTools로 들여다본다.
  loggingBehavior: 'none',
}

export default config
