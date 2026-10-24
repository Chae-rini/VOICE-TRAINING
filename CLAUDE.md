# 프로젝트: 한국어 화자 기준 보이스 트레이닝 iOS 앱 (가칭 VoicePractice)

## 목적
트랜스 여성을 1순위로, 원하는 목소리를 찾고 싶은 사람을 위한 보이스 트레이닝 iOS 앱.
Voice Tools 앱에서 영감을 받았지만, 한국어 화자 기준(모음별 공명, 문장 끝 억양,
한국어 연습 문장)으로 만드는 것이 차별점이다. 화면·이름·아이콘은 Voice Tools를 따라 하지 않는다.

## 원칙 (모든 작업에서 지킬 것)
1. 분석은 신호처리(DSP)로 한다. 피치(F0)·포먼트·음량은 직접 계산하고, AI는 보조 역할만.
2. 음성은 기기 안에서만 처리한다. 녹음을 서버나 외부 API로 보내지 않는다. 네트워크 코드 없음.
3. "남성/여성" 판정·점수·라벨을 표시하지 않는다. 사용자가 정한 목표 범위만 보여준다.
4. 성대 건강을 지킨다. 연습 시간 알림, 무리한 고음 연습을 부추기지 않는 문구.
5. UI 텍스트는 한국어. 아이폰 세로 화면 기준.

## 기술 스택
- Swift + SwiftUI, 최소 지원 iOS 17
- 오디오: AVAudioEngine (입력 탭), AVAudioSession
- 신호처리: Accelerate (vDSP). 외부 패키지는 꼭 필요할 때만, 추가 전에 이유를 설명할 것.
- 그래프: SwiftUI Canvas + TimelineView
- 저장 (3단계부터): 앱 Documents 폴더 + SwiftData

## 폴더 구조
- Audio/   : 마이크 입력, 피치 검출 등 오디오 처리
- Views/   : 화면
- Models/  : 데이터 구조, 연습 문장

## 로드맵
- 1단계: 마이크 입력 + 실시간 피치 그래프 + 목표 범위 띠 + 한국어 문장 카드
- 2단계: 최근 10초 녹음·재생, 연습 시간 알림
- 3단계: 날짜별 녹음 저장·비교
- 4단계: 한국어 모음별 포먼트(F1·F2) 시각화 (LPC, vDSP)
- 5단계: 문장 단위 억양 곡선

## 작업 방식
- 사용자는 비전공자이고 Swift가 처음이다. 작업이 끝나면 무엇을 왜 그렇게 했는지 짧게 설명한다.
- 한 번에 한 단계씩만 진행한다.
- 코드를 바꾼 뒤에는 xcodebuild로 시뮬레이터 대상 빌드를 돌려 컴파일 에러가 없는지 확인한다.
- 프로젝트 설정 파일(.xcodeproj)을 직접 수정해야 하면, 먼저 사용자에게 Xcode에서 할 수 있는 방법을 안내한다.
- 세션이 끝날 때 PROGRESS.md에 "완료한 것 / 다음 할 일 / 알려진 문제"를 갱신한다.

## 개발 메모 (빌드·테스트 명령)
- 이 Mac의 `xcode-select`는 Command Line Tools를 가리킨다. `sudo` 없이 Xcode를 쓰려면
  명령 앞에 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 붙인다.
- 빌드: `xcodebuild -project VoicePractice.xcodeproj -scheme VoicePractice -destination 'generic/platform=iOS Simulator' build`
- 테스트: `xcodebuild -project VoicePractice.xcodeproj -scheme VoicePractice -destination 'platform=iOS Simulator,name=<시뮬레이터 이름>' test`
- 앱 타깃은 기본 격리가 MainActor(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)다.
  오디오 스레드에서 도는 코드(`PitchDetector`, `PitchTapProcessor`, `PitchReading`)는 `nonisolated`로 둔다.
- 파일은 `VoicePractice/`, `VoicePracticeTests/` 폴더에 넣기만 하면 자동으로 프로젝트에 포함된다(동기화 폴더).
- `xcodebuild test`가 끝나면 시뮬레이터가 꺼질 때가 있다. 화면 확인 전에 `xcrun simctl boot <기기>`로 다시 켠다.
- 오디오 스레드에서 불리는 클로저(탭 블록 등)는 메인 액터 코드 안에서 만들지 않는다. 재생 끝 감지는 완료 콜백 대신 메인 액터의 취소 가능한 타이머로 한다.
- 오디오 설정: 녹음은 `.playAndRecord` + `.measurement`(분석용), 듣기는 `.playback`(아이폰 스피커 음량 때문). 설정이 바뀌므로 녹음 엔진·재생 엔진을 단계마다 새로 만든다 (`AudioInputManager`).
- 빌드 설정(`INFOPLIST_KEY_…`)으로 넣을 수 없는 앱 정보(예: `CFBundleDocumentTypes`)는 프로젝트 맨 위의 `VoicePractice-Info.plist`에 둔다. `VoicePractice/` 동기화 폴더 안에 두면 리소스로도 복사돼 빌드가 충돌한다.
- 다른 앱의 공유 창으로 받은 파일은 iOS가 `tmp/<번들 ID>-Inbox/`에 복사해 준다 (iOS 27 시뮬레이터 확인).
- 번들 ID와 팀 ID는 깃에 올리지 않는 `Signing.local.xcconfig`에 있다 (공개 저장소에 실명이 드러나지 않게). 저장소의 `Signing.xcconfig`에는 자리표시자 `com.example.VoicePractice`만 있다. Xcode의 Signing & Capabilities 화면에서 바꾸면 프로젝트 파일에 다시 적히므로 이 파일을 고친다. 시뮬레이터에 예전 번들 ID의 앱이 따로 남아 있을 수 있다.
- 공개 저장소에 올리기 전에 실명·학교 메일·개인 녹음 자료가 들어가지 않았는지 확인한다. 커밋 이메일은 GitHub noreply 주소를 쓴다.
