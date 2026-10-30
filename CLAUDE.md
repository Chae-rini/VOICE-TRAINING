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
- 웹(PWA)·안드로이드(APK) 버전 (2026-10-25 시작, 계획은 `Docs/WEB_PLAN.md`): W0 준비 ✅ / W1 분석 코드 ✅ / W2 마이크 입력 ✅ / W3 [높이] 화면 ✅ / W4 연습 흐름 ✅ / W5 탭 + [모음] ✅ / W6 내 기록 폴더 ✅ / W7 기록 남기기 ✅ / W8 [기록] 화면 ✅ / W9 두 녹음 비교 ✅ / W10 PWA·배포 / A1·A2 APK (2026-10-25 사용자 결정: 웹 먼저, 기록은 브라우저가 아니라 내 폴더·휴대폰에 파일로)
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
- 문장 끝 종류(2026-10-26, 요약 카드의 구절 목록): 안정 회색(`inactive`), 올라감 청록(iOS `.teal`, 웹 `--ending-rise`), 내려감 연한 주황(주황 60%), 크게 내려감 주황(웹 `--warning`). 하강 폭 순서를 안정을 가운데 둔 두 갈래 색으로 보인다. 색은 화살표에만 칠하고 이름(안정·올라감·내려감·크게 내려감)을 같이 쓴다. 분홍·파랑·빨강은 쓰지 않는다.

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
- 정지(직접·전화·백그라운드)로 끊은 녹음은 `RecordingTimeline.keep(_:stopped:)`가 목소리가 0.5초(`minimumStoppedTakeVoicedSeconds`, 임시값) 미만이고 그 전 녹음이 있으면 버린다 — 그 전 녹음·그래프를 그대로 두고 연습 기록에도 넣지 않는다. ‘지금 들어보기’로 끝낸 녹음은 늘 남긴다. 웹은 `keepsEarlierTake`(`web/src/practice/take.ts`, 같은 값) (2026-10-30, 반복 루프가 저절로 시작한 빈 녹음이 방금 들은 녹음을 덮어쓰던 버그)
- 문장 끝 숫자는 기록에도 남는다(2026-10-30~): 연습 기록의 녹음마다(`PracticeTake`)와 남긴 녹음(`SavedRecording`)에 `phrase…` 칸 7개(모두 옵셔널, 비어 있으면 그 전 기록). 칸↔`PhraseEndingSummary`는 `PhraseEndingSummary.restored`, 연습 전체는 저장하지 않고 `PhraseEndingSummary.combined`로 녹음마다를 더한다(비율 두 개는 분모가 없어 합치지 않음). 기록에서 쓰는 글(`headline(rules:)`·`shortPhrase`·`requestLines(rules:combinedTakeCount:)`)은 `PhraseEndingText.swift`의 `PhraseEndingSummary` 확장 — 녹음 하나의 분석 글도 이것을 부른다. SwiftData에 옵셔널 칸을 더하는 것은 자동 이전으로 예전 기록이 그대로 열린다(예전 앱으로 만든 저장소에 새 앱을 덮어 깔아 확인). 웹(2026-10-31)은 녹음마다(`TakeRecord`)·남긴 녹음(`RecordingRecord`)에 선택 칸 `phraseEndings`(같은 숫자 7개를 묶음 하나로, `web/src/model/records.ts`의 `phraseNumbers`·`phraseSummaryOf`), 글·합치기는 `web/src/text/phraseEnding.ts`의 `summary…`·`combinedPhraseSummary`. `FORMAT_VERSION`은 올리지 않았다(예전 앱도 모르는 칸을 펼쳐 그대로 다시 쓴다). `web/test/phraseRecords.test.ts`가 iOS `PhraseEndingRecordTests`와 같은 숫자로 같은 글을 기대한다
- `xcodebuild test`는 시뮬레이터 복제본에서 돌아서, 원래 시뮬레이터에 깔린 앱은 바뀌지 않는다. 고친 앱을 화면으로 확인하려면 `-destination 'platform=iOS Simulator,id=<기기>' -derivedDataPath <임시 폴더> build`로 빌드해 `xcrun simctl install`로 깐다 (2026-10-30, 예전 앱으로 확인할 뻔함)
- `PracticeArchive`의 남기기·지우기는 `throws`다. 영구 저장에 성공한 뒤에만 화면에 완료를 표시하고, 실패하면 저장소가 바꾼 내용을 되돌린다(`rollback`). `try?`로 버리지 않는다. 테스트에서는 `simulatedSaveError`(Debug 전용)로 실패를 흉내 낸다.
- 검증 루프(2026-10-25): 새 빌드 폴더로 Debug·Release 빌드(경고 0), Swift 6 엄격 모드 빌드(`SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete`, 오류·경고 0), 테스트 전체, 저장소를 새로 받아 `Signing.local.xcconfig` 없이 빌드, 합성 모음 포먼트 검증표(`Tools/FormantValidation`), 시뮬레이터 주요 흐름, 개인정보 검사. 앱은 Swift 5 모드라 일상 빌드에서는 Swift 6 동시성 오류가 안 보이므로 엄격 모드 빌드를 따로 돌린다. SwiftData `@Model`의 속성은 메인 액터 밖이라, 그 안에서 부르는 값 타입 생성자는 `nonisolated`로 둔다.
- 테스트가 하나라도 실패하면 `xcodebuild test`가 시뮬레이터 진단을 모으느라 10분쯤 멈춰 있다가 끝날 수 있다. 실패 내용은 `xcrun xcresulttool get test-results tests --path <xcresult> --format json`으로 본다.
- m4a로 저장할 때 형식은 `UTType.mpeg4Audio`가 아니라 `com.apple.m4a-audio`(`AudioFileDocument.contentType`)를 쓴다. `mpeg4Audio`로 두면 파일 저장 창이 확장자를 .mp4로 붙인다 (2026-10-25 시뮬레이터에서 확인).
- SwiftUI `Path.currentPoint`는 Float 정밀도로 돌아와서 `CGPoint`와 `==`로 비교하면 같은 점도 다르다고 나온다. 이어 그릴지 판단하려면 끝점을 따로 기억한다 (`PitchGraphView`의 세로축 밖 점선).
- 저장된 기록을 지울 때는 `delete(model:)`(한꺼번에 지우기) 대신 하나씩 지운다. 한꺼번에 지우면 화면의 `@Query` 목록이 바로 따라 바뀌지 않는다는 보고가 있어서 피했다 (직접 재현하지는 않음).

## 웹 버전 메모 (`web/`, 2026-10-25~)
- 명령 (저장소 맨 위에서): 테스트 `npm --prefix web test`, 타입 검사 `npm --prefix web run check`(경고도 실패), 빌드 `npm --prefix web run build`, 개발 서버 `npm --prefix web run dev`(이 컴퓨터에서만)
- 휴대폰으로 열어 보기: `npm --prefix web run dev:lan` — 같은 와이파이에서 여는 임시 HTTPS 개발 서버 (`@vitejs/plugin-basic-ssl`이 개발용 임시 인증서를 만든다, 앱에는 안 들어감). 휴대폰 브라우저는 https에서만 마이크를 켜 준다. 터미널의 ‘Network:’ 주소를 열고 인증서 경고를 넘긴다. 다 보면 Ctrl+C로 끈다
  - 개발 서버가 내줄 수 있는 파일은 `web/`과 iOS와 같이 쓰는 JSON 두 개(대본 `PracticeScripts.json`, 문장 끝 기준값 `PhraseEndingRules.json` — 2026-10-25 사용자 승인으로 더함)뿐이다 (`vite.config.ts`의 `server.fs.allow`). 저장소 맨 위의 `Validation/`(개인 녹음 자료)·`Signing.local.xcconfig`·Swift 코드는 403으로 막힌다 (2026-10-25 확인). 이 목록을 넓히지 않는다 (꼭 필요하면 파일 하나씩, 먼저 승인)
- 분석 코드(`web/src/dsp/`)는 iOS 코드를 줄 단위로 옮긴 것이다. **iOS의 분석 코드(PitchDetector·FormantAnalyzer·PitchScale·GraphWindow·PitchHistory·VoiceMeters·PitchSummary·PhraseEndingAnalysis)를 고치면 웹도 같이 고치고**, 정답표를 다시 만든다 (문장 끝 분석의 기준값은 `VoicePractice/Models/PhraseEndingRules.json` 한 파일을 둘이 같이 읽으므로 값만 바꿀 때는 그 파일만 고친다. 화면 글·요청문 단락은 `Models/PhraseEndingText.swift` ↔ `web/src/text/phraseEnding.ts` 두 벌이고, 두 테스트가 같은 문장을 기대한다):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O VoicePractice/Audio/PitchDetector.swift VoicePractice/Audio/FormantAnalyzer.swift VoicePracticeTests/SyntheticVowel.swift Tools/WebGolden/main.swift -o <임시 폴더>/web-golden` → `<임시 폴더>/web-golden web/test/golden/swift-golden.json`
- `web/test/golden.test.ts`가 정답표와 비교한다. 목소리 있음/없음은 하나도 달라서는 안 되고, 숫자는 갈래마다 허용 오차 안이어야 한다 (2026-10-25: 높이 최대 3e-12 Hz, F1·F2 최대 0.002 Hz). 차이표는 `npx vitest run test/golden.test.ts --silent=false`로 본다.
- 구절별 문장 끝 분석은 정답표 대신 입력·기대값 파일 하나(`VoicePracticeTests/PhraseEndingCases.json`)를 iOS(`PhraseEndingAnalysisTests`)와 웹(`web/test/phraseEnding.test.ts`)이 같이 읽어 확인한다 (기대값은 손으로 셈한 값, 허용 오차 1e-9). 경우를 더하거나 기준값을 바꾸면 `python3 -I Tools/PhraseEndingCases/make_cases.py`를 고쳐 다시 만들고 두 테스트를 모두 돌린다. Swift 테스트는 이 파일을 `#filePath` 옆에서 읽는다(시뮬레이터는 Mac의 파일을 읽을 수 있다).
- iOS의 vDSP 계산은 반복문으로 옮겼다. Hamming 창은 iOS와 같은 `0.54 − 0.46·cos(2πn/N)`(N으로 나눔), 표본 줄이기 결과 길이는 `⌊(N − 탭 수)/D⌋ + 1` (정답표로 확인).
- 패키지는 정확한 버전으로 고정하고(`--save-exact`), 나온 지 2주가 지난 버전을 쓴다. TypeScript는 6.x (svelte-check가 7을 아직 지원하지 않음).
- 이 Mac의 Node는 25(홀수, 장기 지원판 아님)다. Vitest 5가 지원 목록에 22·24·26만 적어 설치 때 경고가 나지만, 테스트·빌드는 돈다 (2026-10-25). 문제가 생기면 Node 24 LTS를 설치한다(승인 받기).
- 원칙 2: 외부 폰트·CDN·분석 도구를 쓰지 않는다. `web/index.html`의 CSP가 앱 자신의 파일 말고는 연결을 막는다.
- 안드로이드 앱(APK, 2026-10-26~, 계획은 `Docs/WEB_PLAN.md` ‘APK 계획’): Capacitor 8.5.3이 웹 빌드(`web/dist`)를 앱 안에 넣는다. 설정 `web/capacitor.config.ts`(앱 ID `io.github.chae_rini.ullim`), 안드로이드 프로젝트 `web/android/`
  - 명령: 디버그 APK `npm --prefix web run apk:debug` (웹 빌드 → `cap sync android` → `web/scripts/gradle.sh assembleDebug`). 웹 코드를 고친 뒤에는 꼭 다시 `cap sync`해야 앱에 들어간다
  - 완성 APK `npm --prefix web run apk:release` → `web/android/app/build/outputs/apk/release/app-release.apk`. 서명 키는 저장소 밖 `~/Documents/울림-서명키/`(`ULLIM_SIGNING_DIR`로 바꿈, 깃에 올리지 않음, 비밀번호를 화면·문서에 적지 않음). 새로 내놓을 때마다 `web/android/app/build.gradle`의 `versionCode`를 1씩 올린다. 서명 확인은 `apksigner verify --print-certs`(build-tools, JDK 21)
  - 개발용(디버그 키)과 완성(울림 키) 앱은 앱 ID가 같아 서로 덮어 설치되지 않는다 → 지우고 깔아야 한다. 앱을 지웠다 깔면 새 앱은 예전 앱이 ‘문서/울림’에 만든 파일을 열지도 쓰지도 못해서(안드로이드 11 이상), ‘울림’을 쓰지 못하면 ‘울림-2’ … ‘울림-9’에 새로 쓴다(2026-10-26 사용자 결정 ①, `connectAppFolder`·`openFirstUsableAppFolder`). 쓴 폴더는 화면 설정 `ullim.appRecordRoot`에 기억하고 다음에 먼저 연다. 예전 기록은 그때 저장한 기록 파일(zip)을 ‘기록 파일 불러오기’로 가져온다(안드로이드 파일 선택 창은 예전 앱의 zip도 열 수 있다). 에뮬레이터에서 시험 폴더를 정리할 때는 지우지 말고 `adb shell mv`로 비켜 둔다
  - 완성 앱을 들여다봐야 하면 `capacitor.config.ts`에 잠깐 `android: { webContentsDebuggingEnabled: true }`를 넣어 빌드하고(같은 키라 업데이트로 깔려 기록이 남는다), 끝나면 꼭 지우고 다시 빌드한다
  - 앱 아이콘·시작 화면은 `sh web/scripts/android-icons.sh`로 iOS 아이콘에서 만든다 (손으로 고치지 않는다)
  - **JDK 21이 필요하다**: Gradle 8.14.3(Capacitor 템플릿)은 Java 24까지만 돈다. Android Studio 2026.2에 든 JDK 25로는 안 된다 → Android Studio의 Gradle JDK를 21로, CLI는 `gradle.sh`가 `/usr/libexec/java_home -v 21`로 찾는다
  - 안드로이드 SDK는 `~/Library/Android/sdk`(Android Studio 기본). SDK 라이선스 동의는 사용자가 직접 한다
  - 마이크 권한(`RECORD_AUDIO`·`MODIFY_AUDIO_SETTINGS`)은 `AndroidManifest.xml`에 있다. 평문 통신은 끈다(`usesCleartextTraffic="false"`). 원격 주소(`server.url`)는 쓰지 않는다
  - 자동으로 만들어지는 `android/app/src/main/assets/public`·`capacitor.config.json`과 빌드 결과물은 깃에 올리지 않는다 (`web/android/.gitignore`). 서명 키(`*.jks`·`*.keystore`)도 올리지 않는다 (맨 위 `.gitignore`)
  - 패키지 설치는 `--ignore-scripts`로 했다 (Capacitor 패키지에는 설치 스크립트가 없다)
  - JDK 21은 Homebrew `openjdk@21`(keg-only, `/opt/homebrew/opt/openjdk@21`)로 설치했다(2026-10-26). `gradle.sh`가 먼저 찾는다. Android Studio에서 빌드할 때는 Gradle JDK를 이 경로로 정한다
  - 에뮬레이터(사용자가 만든 `Medium_Phone_API_37.0`, Android 17): 이미 켜져 있으면 같은 에뮬레이터를 또 띄우지 않는다(실패한다). 설치·실행 `~/Library/Android/sdk/platform-tools/adb install -r web/android/app/build/outputs/apk/debug/app-debug.apk` → `adb shell am start -n io.github.chae_rini.ullim/.MainActivity`. 화면은 `adb exec-out screencap -p`, 누르기는 `adb shell input tap x y`(기기 픽셀), 버튼 위치는 `adb shell uiautomator dump`
  - 에뮬레이터 마이크: `adb emu avd hostmicon`으로 Mac 마이크를 넘기고, macOS가 에뮬레이터(Android Studio)에 마이크를 허락해야 소리가 들어온다(시스템 설정은 사용자가 직접, 허락 뒤 에뮬레이터를 **새로** 켜야 적용). Android Studio 안에 끼워 켠 에뮬레이터는 Android Studio를 꺼도 화면 없이 남는다 → `adb emu kill`로 끈다. 2026-10-26 확인: 에뮬레이터로 들어온 마이크 소리가 약 8 ms마다 끊겨 높이를 잴 수 없었다(맥북 덮개를 닫아 블루투스 스피커 마이크가 입력). 실제 마이크 높이는 실제 폰이나 Mac Chrome의 웹으로 확인한다
  - 반복 루프에서 다 들은 뒤에는 자동으로 다음 녹음이 시작된다. 그때 ‘정지’를 누르면 새 녹음에 목소리가 0.5초 미만이면 버리고 방금 들은 녹음을 남긴다 (2026-10-30 고침, 그 전에는 빈 새 녹음이 ‘마지막 녹음’이 됐다)
  - 앱 안 웹 화면 들여다보기: `adb shell cat /proc/net/unix`에서 `webview_devtools_remote_<pid>`를 찾아 `adb forward tcp:9333 localabstract:…` → `curl localhost:9333/json`의 웹소켓 주소로 Chrome DevTools Protocol(`Runtime.evaluate`, `userGesture: true`면 누른 것처럼). 디버그 빌드만 된다. 콘솔은 `adb logcat`의 `Capacitor`·`chromium`
  - 안드로이드 웹뷰에서 안 되는 것(A1 확인): 파일 내려받기(아무 일도 없음), Web Share(없음), `showDirectoryPicker`(있지만 바로 AbortError). 복사(`navigator.clipboard`)·파일 선택 창(`<input type=file>`)은 된다
  - 앱 저장·공유(A2): `isNativeApp()`(`src/platform/app.ts`)로 가른다. 기록은 `NativeFolder`(`src/storage/nativeFolder.ts`, 공용 ‘문서/울림’)를 `recordStore`가 앱을 켤 때 자동으로 연다(`connectAppFolder`). 파일로 저장·기록 파일로 저장은 ‘문서/울림/내보낸 파일’, 공유는 `@capacitor/share`(파일은 앱 임시 폴더에 쓴 뒤) — `src/platform/nativeShare.ts`, `src/practice/sharing.ts`의 `saveFile`·`shareText`·`shareFeedback`. 화면 코드는 웹과 같고 문구만 `store.isApp`으로 바꾼다
  - 안드로이드에는 파일 내용을 base64 글자로만 넘길 수 있다(Blob은 웹에서만). 큰 녹음은 768 KB씩 나눠 이어 쓴다(`writeNativeBytes`). 없는 파일은 앱이 기기마다 다른 문구의 오류를 내서, 먼저 `stat`으로 있는지 본다. **공용 폴더에서는 같은 이름에 바로 덮어쓴다** — “임시 파일에 쓰고 → 원래 파일 지우고 → 이름 바꾸기”를 하면 안드로이드의 미디어 목록(MediaProvider)이 뒤늦게 따라오다 어긋나, 이 앱도 열 수 없는(EACCES) 파일이 생긴다(2026-10-26 에뮬레이터에서 실제로 겪음)
  - `capacitor.config.ts`의 `loggingBehavior: 'none'`: 디버그 빌드 로그가 녹음 파일 내용(base64)을 통째로 찍어서 껐다. 앱 안 연습 흐름을 시험할 때는 DevTools 연결에서 `Runtime.queryObjects`로 `lastTake`·`stop`이 있는 객체(session)를 찾아 쓴다(빌드된 앱이라 import로 꺼낼 수 없다)
  - 휴대폰 앱처럼(1묶음, 2026-10-26): 앱일 때만 `main.ts`가 `installNativeApp()`(`src/platform/nativeApp.ts`)을 부른다 — `html.app` 스타일(글자 선택·누를 때 깜빡임 없음, 입력 칸만 선택), 확대 막기, 뒤로 버튼, 화면이 가려지면(`visibilitychange` hidden: 홈·다른 앱·전화) 연습 정지. 공유 창·마이크 허용 창은 가려진 것이 아니다(에뮬레이터 확인)
    - **뒤로 버튼 순서**: 열린 `<dialog>`(‘cancel’을 보내 창 스스로 막을 수 있게) → `onBack`으로 건 처리 함수(나중에 건 것부터) → [높이] 탭으로 → [높이]에서는 `App.minimizeApp()`(앱을 끄지 않고 뒤로 보냄). 새로 여닫는 화면 조각(메뉴·자세히 화면)을 만들면 `onBack(() => …)`을 `onMount`에서 걸고, **다른 탭에 가려져 있으면 false**를 돌려준다(`checkVisibility()`나 `navigation.tab`으로)
    - 진동은 `vibrate('light'|'heavy')`(`src/platform/haptics.ts`, 웹에서는 아무 일도 안 함): iOS `sensoryFeedback`과 같은 때(지금 들어보기로 녹음이 끝날 때 약하게, 쉬어 가기 안내 때 강하게)
    - 앱에 보이는 문구에 ‘브라우저·페이지·새로 고침’을 쓰지 않는다: 둘 다 보일 수 있는 문구 함수는 `isApp = isNativeApp()` 인자를 받는다(`MicError.message`, `processingNotice`, `parseFailureMessage`). 웹에서만 보이는 갈래(폴더 고르기 등)는 그대로
    - 글자 크기: 안드로이드 웹뷰가 휴대폰 글꼴 크기 설정을 이미 따른다(에뮬레이터 1.3배 → 16px이 20.8px). 따로 고치지 않는다
    - 시스템 막대는 Capacitor 8 기본(SystemBars, 기기 밝기 모드를 따름, `viewport-fit=cover` + `env(safe-area-inset-*)`). 다크 모드 시작 화면 바탕은 `res/values-night/styles.xml`. 테마 아이콘 단색 층 `res/drawable/ic_launcher_monochrome.xml`은 손으로 그린 선 그림(`android-icons.sh`가 만들지 않음)
    - 에뮬레이터 시험 팁: 앱을 지웠다 깔면 마이크 권한도 사라진다 → `adb shell pm grant io.github.chae_rini.ullim android.permission.RECORD_AUDIO`. 에뮬레이터 마이크로는 목소리가 안 잡혀 요약 카드가 안 생기므로, DevTools 연결에서 합성 WAV를 `DataTransfer`로 [높이] 아래 파일 칸(`main` 밖의 `input[type=file]`)에 넣고 `change`를 보낸다. 디버깅은 `capacitor.config.ts`에 `android: { webContentsDebuggingEnabled: true }`를 **잠깐** 넣어 완성 APK를 만들고, 확인 뒤 지우고 다시 빌드한다
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
  - 탭(W5): 화면 셋은 `App.svelte`에서 숨기기만 한다(문장 카드 위치·스크롤 유지). 숨은 화면의 그림은 쉬게 `active`를 넘긴다. 녹음·듣기 조작(`PracticeControls`)과 연습 흐름(`session`)은 [높이]·[모음]이 하나를 같이 쓴다. 재기는 기준 목소리(10초)·모음(3초) 둘 다 `session`의 재기 단계이고 `measuringVowel`로 가른다
  - [모음] 확인: 개발 서버의 ‘테스트 모음으로 재기 (개발용)’는 배음 크기를 공명 모양(500·1500·2500·3500 Hz)으로 바꾼 합성음이다. 모음마다 다른 소리로 보려면 페이지에서 `await import('/test/signals.ts')`의 `SyntheticVowel.make`로 WAV를 만들어(`/src/audio/wav.ts`의 `encodeWav`) 파일 고르기에 넣는다. 같은 주소로 `import`한 모듈은 화면과 같은 것이라 `session`을 직접 부를 수도 있다
  - 휴대폰용 `dev:lan`(5173)이 켜져 있을 때 Claude의 미리보기 브라우저는 그 임시 인증서를 막는다 → `.claude/launch.json`의 `web-check`(http, 5174, 이 컴퓨터만)를 같이 켜서 본다
  - 내 기록 폴더(W6, `src/storage/`): 목표 범위·기준·모음 지도는 브라우저가 아니라 고른 폴더의 `울림-설정.json`에 둔다(연습 기록은 `울림-기록.json`, 녹음은 `녹음/`). 브라우저에는 폴더 연결 정보(IndexedDB)와 화면 설정(localStorage)만. **읽지 못한 기록 파일은 절대 덮어쓰지 않는다**. 파일 모양을 바꾸면 `FORMAT_VERSION`을 올리고 예전 판을 읽는 길을 남긴다
  - 미리보기 브라우저에서 폴더 고르기 창은 누를 수 없다 → 페이지에서 `(await import('/src/storage/recordStore.svelte.ts')).store.connectHandle(await navigator.storage.getDirectory())`로 브라우저 안의 시험 폴더(OPFS)를 기록 폴더처럼 연결해 확인한다. 사파리처럼 폴더를 못 고르는 경우는 주소 끝에 `?nofolder`(개발 서버만). 확인 뒤 OPFS·IndexedDB(`ullim`)·localStorage를 지운다
  - 개발 서버가 켜진 뒤 고친 파일은 Vite가 화면 쪽 import 주소에 `?t=시각`을 붙인다. 그러면 페이지에서 `import('/src/…')`로 부른 모듈이 화면과 다른 사본이 되어 시험이 엉뚱하게 돈다 → 코드를 고친 뒤 페이지 JS로 확인할 때는 미리보기 서버를 껐다 켠다
  - 기록(W7): 정지할 때 연습 기록(30초·목소리 5초 이상), ‘기록에 남기기’는 WAV를 `녹음/`에 먼저 쓰고 기록을 더한다(소리를 못 쓰면 기록도 안 남김). 모든 기록에 `id`가 있어 폴더를 고르기 전에 쌓인 기록을 합칠 때 겹치지 않는다. 모르는 모양의 기록도 지우지 않고 그대로 다시 쓴다
  - [기록] 화면 확인(W8): 개발 서버 주소 끝에 `?seed`를 붙이면 기록 폴더에 연결돼 있지 않고 연습 기록이 없을 때만 가짜 기록 40일치를 화면에 넣는다(`model/sampleHistory.ts`, 배포 빌드에는 없음). 다 보면 ‘모든 기록 지우기’
  - Svelte에서 겪은 것(W9): ① `$effect` 안에서 부른 함수가 상태를 읽고 쓰면 그 상태에 따라 효과가 다시 돌아 끝없이 반복된다(`effect_update_depth_exceeded`) → 부르는 쪽을 `untrack(() => …)`으로 감싼다 ② 키가 있는 `{#each … (key)}`에 같은 키가 둘 생기면(`[a, b]`에서 A·B가 같은 녹음) 오류로 화면 갱신이 멈춘다 → 키를 쓰지 않거나 두 칸을 따로 그린다. 오류는 미리보기 브라우저 콘솔(`read_console_messages`)에서 보인다
  - 페이지 JS로 버튼·줄을 찾을 때 클래스 이름(`.row` 등)은 다른 화면의 같은 이름과 겹친다(숨은 [높이] 화면이 DOM 앞쪽에 있다). `.list .row`, `.detail button`처럼 범위를 좁혀 찾는다
  - CSP(`connect-src 'self'`) 때문에 페이지에서 `fetch(blob:…)`는 막힌다. 내려받은 파일을 시험으로 확인할 때는 `URL.createObjectURL`을 가로채 Blob을 직접 받는다
  - Svelte 컴포넌트의 스타일은 그 컴포넌트 안의 같은 클래스 이름에 모두 걸린다. 배치용 `div`와 버튼에 같은 클래스(`.main`)를 쓰면 버튼 배경이 화면 전체에 칠해진다 (2026-10-25에 겪음)
