# 프로젝트: 울림 (Ullim) — 한국어 화자 기준 보이스 트레이닝 iOS 앱

## 목적
앱 이름은 **울림**(로마자 Ullim, 2026-10-25 정함). 울림은 공명(resonance)의 우리말로,
이 앱의 핵심 방향인 모음별 공명을 담았다. 사용자에게 보이는 이름만 울림이고, 내부 프로젝트 이름은 VoicePractice다.

원하는 목소리를 찾는 모든 사람을 위한 보이스 트레이닝 iOS 앱.
트랜스 여성만이 아니라 목소리가 낮아 고민인 사람, 더 낮고 안정된 목소리를 원하는 사람,
발표·면접을 연습하는 사람까지 포함한다. 높이기·낮추기 어느 방향도 가정하지 않는다.
기능을 정할 때의 판단 기준은 매일 연습하는 실제 사용자(개발자 본인)다.
Voice Tools 앱에서 영감을 받았지만, 한국어 화자 기준(모음별 공명, 문장 끝 억양,
한국어 연습 문장)으로 만드는 것이 차별점이다. 화면·이름·아이콘은 Voice Tools를 따라 하지 않는다.
(2026-10-25 방향 전환: 이전에는 "트랜스 여성을 1순위로"였다.)

## 원칙 (모든 작업에서 지킬 것)
1. 분석은 신호처리(DSP)로 한다. 피치(F0)·포먼트·음량은 직접 계산하고, AI는 보조 역할만.
2. 앱은 네트워크 코드를 쓰지 않는다. 녹음과 수치는 사용자가 iOS 공유 창이나 파일 저장 창(‘파일로 저장’, 2026-10-25)에서 직접 고른 경우에만 앱 밖으로 나간다. 자동 전송·업로드는 하지 않는다.
3. "남성/여성" 판정·점수·라벨을 표시하지 않는다. 사용자가 정한 목표 범위만 보여준다. 높이기·낮추기 어느 방향도 기본으로 가정하지 않는다.
4. 성대 건강을 지킨다. 연습 시간 알림, 무리한 고음·저음 연습을 부추기지 않는 문구.
5. UI 텍스트는 한국어. 아이폰 세로 화면 기준.
6. 의료 기기가 아니다. 진단·치료·재활 효과를 주장하는 문구를 쓰지 않는다.

## 기술 스택
- Swift + SwiftUI, 최소 지원 iOS 17
- 오디오: AVAudioEngine (입력 탭), AVAudioSession
- 신호처리: Accelerate (vDSP). 외부 패키지는 꼭 필요할 때만, 추가 전에 이유를 설명할 것.
- 그래프: SwiftUI Canvas + TimelineView (실시간 그래프), Swift Charts ([기록] 탭의 날짜별 그래프, 애플 기본 프레임워크)
- 저장 (3단계부터): 앱 Documents 폴더 + SwiftData

## 폴더 구조
- Audio/   : 마이크 입력, 피치 검출 등 오디오 처리
- Views/   : 화면
- Models/  : 데이터 구조, 연습 문장

## 로드맵 (2026-10-25 기준, 실제로 만든 것)
완료
- 1단계 ✅ 마이크 입력 + 실시간 피치 그래프(꺾은선, 목표 범위 띠·슬라이더) + 한국어 연습 문장 카드
  - 문장: 직접 쓴 문장 15개, 패턴 자동 생성, 낭독 대본 200편
  - 피치 검출(YIN)은 실제 녹음 32개로 Praat와 비교 검증 (임계값 0.20)
- 2단계 ✅ 녹음·재생 연습
  - 실시간 자동 녹음: 정지할 때까지 녹음, 최근 N초(10초~3분)만 보관, "지금 들어보기" → 다 들으면 자동으로 다시 녹음
  - 연습 시간 알림: 쉬지 않고 15분 연습하면 쉬어 가기 안내
  - 재생 음량 보정 (아이폰 70% 음량에서 확인)
- 2단계 추가분 ✅ 녹음 파일 불러오기(파일 앱, 음성 메모 공유 창) + 피치 요약 카드 + AI 피드백용 공유(사용자가 고른 앱으로만: 요약 글만 / 녹음 파일과 함께)
- 목표 범위 기준 녹음 ✅ 내 목소리를 먼저 재고(10초 또는 녹음 파일), 기준 중앙값을 점선으로 표시, 처음 목표 범위는 기준 ±20 Hz (저장된 목표 범위는 바꾸지 않음)

다음 순서
1. 4단계: 한국어 모음별 포먼트(F1·F2) 시각화 (LPC, vDSP) — 아이폰 확인만 남음
   - 4-1 ✅ 포먼트 분석기 + 합성 모음 검증 / 4-2 ✅ 실시간 모음 지도 (탭 [높이]·[모음]) / 4-3 ✅ 내 모음 지도 저장·비교 / 4-4 아이폰 확인
   - 성별 평균 포먼트표는 화면에 쓰지 않는다 (원칙 3). 비교 대상은 내가 잰 내 모음 지도뿐이다
2. 3단계: 날짜별 기록·변화 보기 + 연습 알림 — 진행 중
   - 3-1 ✅ 저장 기반: 연습 한 번 요약 자동 저장(숫자만), ‘기록에 남기기’(소리 m4a + 요약 + 메모), 내 목소리·모음 재기 이력, 연습 언어 표시
   - 3-2 ✅ [기록] 탭(기간·언어 거르기, 연습마다 높이·날마다 연습 시간 그래프, 남긴 녹음 재생·메모·언어 고치기, 하나씩·모두 지우기)
   - 3-3 ✅ 두 녹음 비교(A·B 수치·높낮이 폭·높이 분포, 하나씩·이어 듣기)
   - 3-4 ✅ 연습 알림(로컬 알림, 기본 꺼짐, 오후 8시, 연습한 날 건너뜀, 14일치 예약)
   - 녹음마다 분석 로그 ✅ 연습 중 녹음마다 요약 숫자를 연습 기록에 쌓고, [기록] → 연습 기록에서 보고 AI에게 보내기 (숫자만)
   - 3-5 아이폰 확인
   - 점수·등급·향상률·연속 기록(스트릭)은 쓰지 않는다. 숫자와 그래프만 보여 준다

그 뒤 (순서 미정)
- 웹(PWA)·안드로이드(APK) 버전 (2026-10-25 시작, 계획은 `Docs/WEB_PLAN.md`): W0 준비 ✅ / W1 분석 코드 ✅ / W2 마이크 입력 ✅ / W3 [높이] 화면 ✅ / W4 연습 흐름 ✅ / W5 PWA·배포 / A1·A2 APK (2026-10-25 사용자 결정: 웹 먼저)
- 5단계: 문장 단위 억양 곡선
- 외국어 연습 (2026-10-25 아이디어: 외국어로 말할 때 피치가 많이 달라진다): 영어 발표·일본어 스피치 연습 문장과 대본, 언어별 기준 목소리, 일본어 5모음 지도, 언어별 억양(5단계와 이어짐). 화면 글자는 한국어 그대로

보류
- 아이패드 버전 (2026-10-25 보류)

## 작업 방식
- 사용자는 비전공자이고 Swift가 처음이다. 작업이 끝나면 무엇을 왜 그렇게 했는지 짧게 설명한다.
- 한 번에 한 단계씩만 진행한다.
- 코드를 바꾼 뒤에는 xcodebuild로 시뮬레이터 대상 빌드를 돌려 컴파일 에러가 없는지 확인한다.
- 프로젝트 설정 파일(.xcodeproj)을 직접 수정해야 하면, 먼저 사용자에게 Xcode에서 할 수 있는 방법을 안내한다.
- 작업 기록은 Docs/CHANGELOG.md에, PROGRESS.md는 짧게 유지한다 (세션마다 읽는 문서가 길면 맥락을 차지해 코드를 볼 여유가 줄어든다).
  - 세션이 끝날 때: 한 일은 Docs/CHANGELOG.md 맨 아래에 날짜와 함께 더하고, PROGRESS.md는 "현재 상태(한 단락) / 다음 할 일 / 알려진 문제"만 고친다. 해결된 문제와 끝난 할 일은 PROGRESS.md에서 빼서 CHANGELOG로 옮긴다.
  - 파일을 더하거나 역할이 바뀌면 Docs/FILES.md를, 아이폰에서 직접 확인할 것이 생기면 Docs/DEVICE_TEST.md를 고친다.

## 색 (2026-10-25, 아이콘의 네 색)
화면은 색 이름 대신 역할 이름(`UllimColor`, `Views/UllimTheme.swift`)을 쓴다. 색 값은 `Assets.xcassets`의 색 세트에 있다.
| 역할 | 색 | 쓰는 곳 |
|---|---|---|
| `voice` 지금 내 목소리 | 분홍 (아이콘의 파형) | 피치 꺾은선(목표 안), 지금 높이 숫자, 모음 지도의 지금 점, [기록] 그래프의 점, 듣는 중 |
| `target` 강조색·목표 범위 | 파랑 (가장 큰 원) = `AccentColor` | 버튼·슬라이더·탭, 목표 범위 띠 |
| `reference` 내 기준 | 보라 | 기준 목소리 점선, 내 모음 지도, 내 목소리 재기 화면·버튼, 두 녹음 비교의 A |
| `record` 기록·저장 | 초록 | 연습 시간 막대, 저장 완료 안내, ‘기록에 남기기’, 두 녹음 비교의 B |
| `inactive` | 회색 | 목표 밖의 점, 꼬리 |
- 빨강(녹음 중·정지)과 주황(주의)은 시스템 색 그대로.
- 분홍과 파랑은 성별과 묶여 읽히기 쉬워서 "높은 쪽/낮은 쪽", "전/후" 짝으로 쓰지 않는다 (원칙 3). 분홍은 목표가 어디든 늘 "지금 내 목소리"다.
- 밝은 모드 값은 아이콘 색과 같은 색상에서 밝기만 낮춰 흰 바탕·카드 바탕 대비 4.5:1 이상, 어두운 모드 값은 아이콘 색 그대로. 강조색은 흰 글자가 얹히므로 어두운 모드에서도 진한 파랑(#0F7AC0). 같은 이유로 흰 글자가 얹히는 보라 채운 버튼(borderedProminent)은 `UllimColor.referenceFill`(두 모드 모두 #8C42E1)을 쓴다. `UllimThemeTests`가 대비를 확인한다.
- 색에만 기대지 않는다: 목표 안·밖은 색과 함께 선 굵기(안 3.5pt, 밖 2pt)와 글자("· 목표 범위 안")로도 알린다. 그림(Canvas) 그래프에는 VoiceOver 설명(`accessibilityValue`)을 붙인다.
- 큰 글자: 화면 아래 고정 영역은 xxxLarge까지, 그래프 안 글자는 xxLarge까지만 커진다. 고정 높이가 필요한 곳(넘기는 문장 카드 등)은 `@ScaledMetric`으로 높이도 같이 키운다. UIKit 글 상자(`WordWrappedText`)는 SwiftUI의 `dynamicTypeSize`를 읽어 기본 크기에서 한 번만 키운다.
- 언어 구분은 색 대신 점 모양(원·네모·세모·마름모)으로 한다.

## 높이 눈금 (2026-10-25, 반음)
- 목소리 높이(Hz)를 그리는 그래프는 반음(로그) 눈금이다: [높이] 그래프·목표 슬라이더(Canvas, `PitchScale.position`), [기록] 그래프·두 녹음 비교 분포(Swift Charts, `.chartYScale/.chartXScale(domain:, type: .log)`). 같은 반음 흔들림이 낮은 목소리든 높은 목소리든 같은 길이로 보여야 한다 (원칙 3).
- 반음 계산은 `Models/PitchScale.swift` 한곳에 둔다 (반음 거리 12·log₂(b/a), 반음 옮기기, 위치, 눈금 숫자). 새 높이 그래프도 이것을 쓴다.
- 눈금 숫자는 Hz로 쓰고 음이름은 쓰지 않는다. 숫자는 `PitchScale.ticks(in:)`가 고른다 (70·100·150·200·300·400, 좁으면 더 촘촘히).
- 축의 여유·최소 폭은 반음으로 센다 (`PracticeHistory.pitchPaddingSemitones` 1.5, `minimumPitchSpanSemitones` 6). 분포 칸은 반음 반 칸, 경계는 440 Hz 기준으로 고정 (두 녹음이 같은 칸을 쓰게).
- 저장값(목표 범위·기준)은 계속 Hz다. 반음 눈금은 그리는 방법만 바꾼다.
- 모음 지도(F1·F2)는 아직 Hz 직선 눈금이다. 포먼트에 맞는 눈금은 따로 정한다.
- [높이] 음량·공명 밝기 막대(2026-10-25, `Models/VoiceMeters.swift`):
  - 음량은 이 기기 마이크 기준 dBFS다. 절대 데시벨(dB SPL)이 아니라고 화면에 밝히고, 크다·작다 평가 문구는 쓰지 않는다. 아주 큰 소리가 이어질 때만 목 상태를 묻는다 (임시 기준 −10 dBFS · 3초, 아이폰 값으로 고칠 것).
  - 공명 밝기는 최근 2.5초 F2 중앙값을 내 기준 F2(기준 목소리 잴 때 저장, `TargetRangeStore.baselineF2Key`)와만 비교한다. 성별 평균·좋고 나쁨 표현은 쓰지 않는다. 문장 속 F2는 말한 모음에 따라 달라지므로 "같은 대본을 읽을 때 비교하면 정확해요" 안내를 빼지 않는다.
  - F2 중앙값은 녹음 묶음·연습 기록·남긴 녹음·기준 이력에도 저장한다 (나중 [기록] 탭 공명 추이용).
- [높이] 그래프 세로축(2026-10-25): 목표 범위 ±50 Hz(분석 범위 70~400 Hz 안, `PitchScale.graphRange`)를 반음 눈금으로. 목표 범위가 없으면 70~400 Hz 전체. 축 밖의 높이는 위·아래 끝에 붙여 회색 점선으로 그린다(`PitchScale.isBeyond`, 끝에 붙인 실선은 평평한 높이로 읽히기 쉬워서). 그래프 높이는 쓸 수 있는 화면 높이의 45%(대본 읽기 33%), 최소 220·150pt, 최대 380·280pt.
- [높이] 그래프 가로축(2026-10-25): 길이 = 녹음할 때의 ‘들려줄 길이’(10초~3분), 오른쪽 끝 = 지금(녹음 중) / 녹음이 끝난 때(멈춘 화면·다시 듣기). 곡선의 머리가 한자리에 있어야 지금 높이를 읽기 쉽다는 사용자 요청. 계산은 `Models/GraphWindow.swift`. 보이는 구간은 녹음 통이 남겨 두는 소리(다시 들을 수 있는 구간)와 같다. 화면 폭보다 촘촘한 점은 픽셀 열마다 하나로 묶어 그린다(`PitchHistory.displaySegments`).

## 개발 메모 (빌드·테스트 명령)
- 내부 프로젝트 이름은 VoicePractice로 유지한다. Xcode 프로젝트·타깃·스킴·폴더·소스의 타입 이름(`VoicePracticeApp` 등)과 번들 ID는 바꾸지 않는다 (바꾸면 빌드 설정이 깨지기 쉽다). 사용자에게 보이는 이름만 "울림"이다.
  - 홈 화면 이름: 빌드 설정 `INFOPLIST_KEY_CFBundleDisplayName = "울림"` (Xcode에서는 타깃 → General → Identity → Display Name과 같은 값)
  - 로마자가 필요한 곳(파일 이름 등)은 "Ullim"으로 쓴다. 공유용 WAV는 `Ullim-날짜.wav`
  - 마이크·알림 권한 창, 공유 창, 알림 배너에 나오는 앱 이름은 iOS가 Display Name을 가져다 쓰므로 따로 넣지 않는다
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
- 연습 기록은 `PracticeArchive` 한곳에서 저장한다. 숫자는 SwiftData(기본 위치 `Library/Application Support/default.store`), 직접 남긴 녹음은 `Documents/Recordings/<UUID>.m4a`(AAC 64 kbps, iOS 백업 제외). 테스트는 `PracticeArchive(inMemory: true, recordingsDirectory: 임시 폴더)`로 앱의 실제 기록을 건드리지 않는다.
- `@MainActor` 정적 속성(예: `PracticeArchive.shared`)을 함수의 기본 인자값으로 쓰면 격리 경고가 난다. 옵셔널 인자로 받고 `?? .shared`로 채운다.
- 시뮬레이터는 마이크 소리가 들어오지 않아 연습 기록이 생기지 않는다. [기록] 탭을 확인할 때는 Debug 빌드를 `xcrun simctl launch <기기> <번들 ID> -seedSampleHistory YES`로 실행하면 연습 기록이 없을 때만 가짜 기록(40일치)을 넣는다 (`Models/SampleHistory.swift`, Release 빌드에는 없음). 확인 뒤 [기록] 탭의 ‘모든 기록 지우기’로 지운다.
- 시뮬레이터 앱의 설정값(UserDefaults)을 바깥에서 바꾸려면 앱을 끈 뒤 `xcrun simctl spawn <기기> defaults write <앱 데이터 폴더>/Library/Preferences/<번들 ID> <키> <값>`처럼 파일 경로로 쓴다 (번들 ID만 주면 다른 곳에 써진다). 연습 알림은 알림 시간을 몇 분 뒤로 바꾸고 앱을 다시 켠 뒤 홈 화면으로 가서 확인한다. 예약·전달 여부는 `log show`에서 SpringBoard의 "pending notification"·"Deliver local notification" 줄로 본다.
- 시뮬레이터에서 SwiftUI 스위치(Toggle)는 도구로 탭하면 안 켜질 때가 있다. 끌면(swipe) 켜진다.
- 시뮬레이터에서 글자 입력: 도구의 text 입력(붙여넣기)은 한글이 안 되고 영어도 들어가지 않을 때가 있다. 화면 자판의 키를 좌표로 직접 누르면 한글도 들어간다.
- 녹음 수치는 녹음 묶음(`RecordedTake`) 안의 점으로만 만든다. 요약 카드·기록에 남기기·AI 공유·다시 듣기 모두. 화면 그래프용 기록(`RecordingTimeline.display`, 여유 2초 포함)과 재기용 기록(`measurement`)은 수치에 쓰지 않는다 (2026-10-25 버그 ①②).
- `PracticeArchive`의 남기기·지우기는 `throws`다. 영구 저장에 성공한 뒤에만 화면에 완료를 표시하고, 실패하면 저장소가 바꾼 내용을 되돌린다(`rollback`). `try?`로 버리지 않는다. 테스트에서는 `simulatedSaveError`(Debug 전용)로 실패를 흉내 낸다.
- 검증 루프(2026-10-25): 새 빌드 폴더로 Debug·Release 빌드(경고 0), Swift 6 엄격 모드 빌드(`SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete`, 오류·경고 0), 테스트 전체, 저장소를 새로 받아 `Signing.local.xcconfig` 없이 빌드, 합성 모음 포먼트 검증표(`Tools/FormantValidation`), 시뮬레이터 주요 흐름, 개인정보 검사. 앱은 Swift 5 모드라 일상 빌드에서는 Swift 6 동시성 오류가 안 보이므로 엄격 모드 빌드를 따로 돌린다. SwiftData `@Model`의 속성은 메인 액터 밖이라, 그 안에서 부르는 값 타입 생성자는 `nonisolated`로 둔다.
- 테스트가 하나라도 실패하면 `xcodebuild test`가 시뮬레이터 진단을 모으느라 10분쯤 멈춰 있다가 끝날 수 있다. 실패 내용은 `xcrun xcresulttool get test-results tests --path <xcresult> --format json`으로 본다.
- m4a로 저장할 때 형식은 `UTType.mpeg4Audio`가 아니라 `com.apple.m4a-audio`(`AudioFileDocument.contentType`)를 쓴다. `mpeg4Audio`로 두면 파일 저장 창이 확장자를 .mp4로 붙인다 (2026-10-25 시뮬레이터에서 확인).
- SwiftUI `Path.currentPoint`는 Float 정밀도로 돌아와서 `CGPoint`와 `==`로 비교하면 같은 점도 다르다고 나온다. 이어 그릴지 판단하려면 끝점을 따로 기억한다 (`PitchGraphView`의 세로축 밖 점선).
- 저장된 기록을 지울 때는 `delete(model:)`(한꺼번에 지우기) 대신 하나씩 지운다. 한꺼번에 지우면 화면의 `@Query` 목록이 바로 따라 바뀌지 않는다는 보고가 있어서 피했다 (직접 재현하지는 않음).

## 웹 버전 메모 (`web/`, 2026-10-25~)
- 명령 (저장소 맨 위에서): 테스트 `npm --prefix web test`, 타입 검사 `npm --prefix web run check`(경고도 실패), 빌드 `npm --prefix web run build`, 개발 서버 `npm --prefix web run dev`
- 분석 코드(`web/src/dsp/`)는 iOS 코드를 줄 단위로 옮긴 것이다. **iOS의 분석 코드(PitchDetector·FormantAnalyzer·PitchScale·GraphWindow·PitchHistory·VoiceMeters·PitchSummary)를 고치면 웹도 같이 고치고**, 정답표를 다시 만든다:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O VoicePractice/Audio/PitchDetector.swift VoicePractice/Audio/FormantAnalyzer.swift VoicePracticeTests/SyntheticVowel.swift Tools/WebGolden/main.swift -o <임시 폴더>/web-golden` → `<임시 폴더>/web-golden web/test/golden/swift-golden.json`
- `web/test/golden.test.ts`가 정답표와 비교한다. 목소리 있음/없음은 하나도 달라서는 안 되고, 숫자는 갈래마다 허용 오차 안이어야 한다 (2026-10-25: 높이 최대 3e-12 Hz, F1·F2 최대 0.002 Hz). 차이표는 `npx vitest run test/golden.test.ts --silent=false`로 본다.
- iOS의 vDSP 계산은 반복문으로 옮겼다. Hamming 창은 iOS와 같은 `0.54 − 0.46·cos(2πn/N)`(N으로 나눔), 표본 줄이기 결과 길이는 `⌊(N − 탭 수)/D⌋ + 1` (정답표로 확인).
- 패키지는 정확한 버전으로 고정하고(`--save-exact`), 나온 지 2주가 지난 버전을 쓴다. TypeScript는 6.x (svelte-check가 7을 아직 지원하지 않음).
- 이 Mac의 Node는 25(홀수, 장기 지원판 아님)다. Vitest 5가 지원 목록에 22·24·26만 적어 설치 때 경고가 나지만, 테스트·빌드는 돈다 (2026-10-25). 문제가 생기면 Node 24 LTS를 설치한다(승인 받기).
- 원칙 2: 외부 폰트·CDN·분석 도구를 쓰지 않는다. `web/index.html`의 CSP가 앱 자신의 파일 말고는 연결을 막는다.
- 브라우저 미리보기: `.claude/launch.json`(깃에 올리지 않음)의 `web-preview`(빌드 결과, 4173)·`web-dev`(5173). Claude의 미리보기 브라우저는 마이크를 막는다 → 개발 서버에서만 보이는 ‘테스트 음 180 Hz (개발용)’ 버튼으로 흐름 전체를 확인하고, 실제 목소리는 사용자가 확인한다 (`Docs/WEB_PLAN.md` 직접 확인)
- 마이크 흐름(W2): 마이크 → 소리 받기 AudioWorklet(`captureProcessor.ts`, 1024샘플씩) → MessageChannel로 분석 Worker에 바로 → 점을 화면으로. 오디오 스레드에서는 분석하지 않는다. 워크릿은 `?worker&url`로, 워커는 `new Worker(new URL(..., import.meta.url), { type: 'module' })`로 불러온다 (Vite 문서 확인)
  - 점의 시각은 AudioContext 시계(`startFrame / sampleRate`), 화면의 지금은 `context.currentTime` — 같은 시계다
  - 소리 받기 노드가 계속 돌도록 출력을 음량 0 GainNode → destination에 잇는다 (스피커로는 안 나감)
  - AudioContext는 버튼을 누른 직후 `getUserMedia`를 기다리기 전에 만든다 (아이폰 사파리 규칙)
  - 자동 처리 끄기는 꼭 지켜야 하는 조건(exact)이 아니다. 못 끄는 브라우저에서도 마이크는 켜지고, 실제 상태(`getSettings`)를 화면에 알린다
- [높이] 화면(W3): 대본은 iOS의 `VoicePractice/Models/PracticeScripts.json`을 직접 읽는다(`vite.config.ts`의 `server.fs.allow`). 직접 쓴 문장·패턴·단어는 `web/src/data/sentences.ts`에 사본이 있고, `web/test/sentences.test.ts`가 iOS Swift 파일과 같은지 확인한다 — **한쪽을 고치면 다른 쪽도 고친다**
  - 설정은 localStorage에 `ullim.` + iOS와 같은 키 이름으로 둔다 (`model/settingsStorage.ts`). 녹음·숫자 기록 저장은 아직 없다 (W4·[기록])
  - ‘내 목소리 재기’는 목표 범위의 출발점이라 W3에 넣었다. 마이크 대신 쓰는 ‘테스트 음 (개발용)’ 버튼은 개발 서버에서만 보인다
  - 반복 루프(W4): 마이크는 루프 동안 켜 두고, 분석 스레드가 ‘begin’~‘finish’ 사이의 조각만 분석·녹음 통에 남긴다 (듣는 동안 스피커 소리가 섞이지 않게). 녹음 묶음 = 분석 스레드가 돌려준 소리 + 화면이 받은 점 중 그 구간. 단계는 `practice/loop.ts`, 흐름은 `practice/session.svelte.ts`
  - 개발 서버에서 주소 끝에 `?mute`를 붙이면 다시 듣기를 소리 없이 재생한다 (테스트 음이 스피커로 나가지 않게)
  - 화면 버튼은 Svelte가 이벤트를 위로 모아 받는다(delegation). 시험 삼아 `dispatchEvent`로 보낼 때는 `{ bubbles: true }`를 줘야 반응한다
  - Svelte 컴포넌트의 스타일은 그 컴포넌트 안의 같은 클래스 이름에 모두 걸린다. 배치용 `div`와 버튼에 같은 클래스(`.main`)를 쓰면 버튼 배경이 화면 전체에 칠해진다 (2026-10-25에 겪음)
