/** 아래 탭: [높이] 피치 연습, [모음] 모음 지도, [기록] 날짜별 기록 (iOS `ContentView.AppTab`) */
export type AppTab = 'pitch' | 'vowel' | 'history'

/** 화면 사이에서 함께 보는 상태: 지금 탭, ‘내 목소리 재기’ 창이 열렸는지 */
class Navigation {
  tab: AppTab = $state('pitch')
  baselineSheetOpen = $state(false)
}

export const navigation = new Navigation()
