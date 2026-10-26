import { Capacitor } from '@capacitor/core'

/**
 * 안드로이드 앱(APK) 안에서 돌고 있는지 (Capacitor). 웹 브라우저에서는 false.
 * 앱의 웹뷰는 내려받기·공유 창·폴더 고르기가 안 되어서(A1 확인), 이 값으로 앱 기능(파일 시스템·공유)을 대신 쓴다.
 */
export function isNativeApp(): boolean {
  return Capacitor.isNativePlatform()
}
