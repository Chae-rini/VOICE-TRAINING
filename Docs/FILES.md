# 파일 안내 (무엇을 하는 파일인지 한 줄씩)

| 파일 | 하는 일 |
|---|---|
| `VoicePractice/VoicePracticeApp.swift` | 앱의 시작점. 앱이 켜지면 첫 화면(ContentView)을 띄우고, 기록 저장소를 화면에 연결한다 |
| `VoicePractice/ContentView.swift` | 첫 화면. 권한이 꺼져 있으면 안내 화면을, 아니면 [높이]·[모음] 탭과 아래 고정된 연습 조작 영역, 말하는 언어 고르기를 보여준다 |
| `VoicePractice/Audio/AudioInputManager.swift` | 마이크·스피커 담당. 연습 고리 순서대로 녹음하고, 들어온 소리를 피치 검출기에 넘기고, 방금 녹음을 들려준다. 정지하면 연습 요약을 기록에 남기고, ‘기록에 남기기’를 누르면 녹음을 저장소에 넘긴다 |
| `VoicePractice/Audio/TakeRecorder.swift` | 녹음 중 들어온 소리 중 최근 N초만 메모리에 남기는 고리 모양 통 (다시 듣기용) |
| `VoicePractice/Audio/AudioFileAnalyzer.swift` | 녹음 파일(음성 메모 등)을 읽어 피치를 미리 계산하고, 공유용 WAV·기록용 m4a 파일을 만드는 도구 |
| `VoicePractice/Models/PitchSummary.swift` | 녹음의 요약 수치(중앙값·범위·목표 범위 안 비율)와 AI에게 보낼 피드백 요청문 |
| `VoicePractice/Views/RecordingSummaryView.swift` | 그래프 아래 요약 카드와 "기록에 남기기"(메모 창)·"AI에게 피드백 받기"·"요약 복사" 버튼, iOS 공유 창 |
| `VoicePractice/Models/PracticeRecord.swift` | 기록의 모양: 말하는 언어, 연습 한 번 모으기 규칙(30초·5초 기준), 저장하는 기록 4가지(연습 요약, 남긴 녹음, 기준 목소리 이력, 모음 이력) |
| `VoicePractice/Models/PracticeArchive.swift` | 기록 저장소: 숫자는 SwiftData, 남긴 녹음은 m4a 파일(백업 제외). 저장·하나 지우기·모두 지우기를 한곳에서 하고, 저장에 실패하면 되돌린 뒤 오류를 알린다 |
| `VoicePractice/Models/RecordedTake.swift` | 녹음 한 번의 묶음: 소리, 시작 시각·길이, 그 구간의 피치·포먼트 점, 남긴 기록의 ID. 요약·저장·공유·다시 듣기는 이것만 쓴다 |
| `VoicePractice/Models/RecordingTimeline.swift` | 녹음·재기 중의 피치 점을 화면 그래프용·재기용으로 나눠 담고, 마지막 녹음 묶음을 들고 있는 곳 |
| `VoicePracticeTests/RecordedTakeTests.swift` | 외부 리뷰 버그 세 개(요약 구간, 재기 덮어쓰기, 저장 실패)의 재현 테스트 |
| `VoicePracticeTests/PracticeRecordTests.swift` | 연습 한 번 모으기 규칙과 저장소(저장·다시 읽기·m4a·백업 제외·하나 지우기·모두 지우기·녹음 이름)를 확인하는 시험지 |
| `VoicePractice/Models/PracticeHistory.swift` | [기록] 탭의 계산 규칙: 기간(7일·30일·전체), 언어 거르기, 날마다 연습 시간, 모아 보기, 그래프 축 범위, 시간 표시 |
| `VoicePractice/Models/SampleHistory.swift` | 개발용 가짜 기록 40일치 (시뮬레이터 확인용, Debug 빌드에서 `-seedSampleHistory YES`일 때만) |
| `VoicePractice/Views/HistoryScreen.swift` | [기록] 탭 화면: 기간·언어 고르기, 모아 보기, 그래프, 남긴 녹음·연습 기록·내 목소리 재기 목록, 모든 기록 지우기 |
| `VoicePractice/Views/HistoryChartView.swift` | [기록] 탭의 그래프 두 개 (연습마다 높이, 날마다 연습 시간). Swift Charts |
| `VoicePractice/Views/RecordingDetailView.swift` | 남긴 녹음 자세히 보기: 수치, 언어·메모 고치기, 다시 듣고 곡선 보기, 지우기 |
| `VoicePracticeTests/PracticeHistoryTests.swift` | [기록] 탭 계산 규칙을 확인하는 시험지 |
| `VoicePractice/Models/RecordingComparison.swift` | 두 녹음 비교의 계산 규칙: 처음 짝(처음·최근), 높낮이 폭(반음), 중앙값 차이 문장, 높이 분포(반음 반 칸), 분포 그래프 축 |
| `VoicePractice/Audio/ComparePlayer.swift` | 두 녹음 비교 전용 재생기: 남긴 녹음 두 개를 읽어 높이를 내고, A·B를 하나씩 또는 이어서 들려준다 |
| `VoicePractice/Views/RecordingCompareView.swift` | 두 녹음 비교 화면: A·B 고르기, 나란히 보기 표, 높이 분포 그래프, 듣기 |
| `VoicePracticeTests/RecordingComparisonTests.swift` | 두 녹음 비교 계산 규칙과 재생기의 파일 읽기를 확인하는 시험지 |
| `VoicePractice/Models/PracticeReminder.swift` | 연습 알림: 알릴 날짜 계산(14일, 연습한 오늘 건너뛰기), 알림 내용, 예약 다시 맞추기, 알림 권한 묻기 |
| `VoicePractice/Views/ReminderSettingsView.swift` | ‘연습 알림’ 화면: 켜기·끄기, 알림 시간, 권한이 꺼졌을 때 안내 |
| `VoicePracticeTests/PracticeReminderTests.swift` | 연습 알림 날짜 계산·알림 내용·오늘 연습 여부를 확인하는 시험지 |
| `VoicePracticeTests/RecordingImportTests.swift` | 파일 분석·WAV 저장·요약 수치·요청문을 확인하는 시험지 |
| `VoicePractice/Models/VoiceBaseline.swift` | 내 기준 목소리 계산(중앙값·범위·목소리 안 잡힘), 처음 목표 범위(±20 Hz), 반음 거리, 목표 범위·기준 저장 규칙(예전 사용자 값 지키기) |
| `VoicePractice/Views/BaselineMeasureView.swift` | "내 목소리 재기" 화면: 문장 읽고 10초 재기 또는 녹음 파일로 재기, 결과와 목표 범위 맞추기 스위치 |
| `VoicePracticeTests/VoiceBaselineTests.swift` | 기준 계산·처음 목표 범위·저장값 유지·목소리 안 잡힘·파일로 재기를 확인하는 시험지 |
| `VoicePractice/Audio/FormantAnalyzer.swift` | 소리 조각 하나에서 포먼트(F1·F2)를 LPC로 재는 계산기 (표본 줄이기, Levinson–Durbin, 다항식 근) |
| `VoicePracticeTests/SyntheticVowel.swift` | 정답 포먼트를 아는 합성 모음 만들기 (Rosenberg 펄스 + 공명기). 테스트와 검증 도구가 함께 쓴다 |
| `VoicePracticeTests/FormantAnalyzerTests.swift` | 포먼트 계산기의 각 단계와 합성 모음 정확도를 확인하는 시험지 |
| `Tools/FormantValidation/main.swift` | 합성 모음으로 F0·차수·창 길이별 포먼트 오차표와 속도를 내는 검사 도구. 앱에는 들어가지 않는다 |
| `VoicePractice/Models/VowelSpace.swift` | 모음 지도 규칙: 축 방향·범위, 지금 점(최근 중앙값), F1 불확실 기준 |
| `VoicePractice/Views/VowelChartView.swift` | 모음 지도 그림 (F1–F2 평면, 지금 점, 꼬리, 불확실 표시, 내가 잰 모음 원, 비교 숫자) |
| `VoicePractice/Views/VowelMapScreen.swift` | [모음] 탭 화면: 모음 지도, 내 모음 지도 재기(모음 고르기·3초 재기·파일로), 보는 법 |
| `VoicePracticeTests/VowelSpaceTests.swift` | 모음 지도 규칙과 파일 분석의 포먼트를 확인하는 시험지 |
| `VoicePractice/Models/VowelMap.swift` | 내 모음 지도: 모음 하나 재기(중앙값·흔들린 범위·F1 불확실), 저장·읽기 |
| `VoicePracticeTests/VowelMapTests.swift` | 내 모음 지도 재기·저장 규칙을 확인하는 시험지 |
| `VoicePractice/Models/PracticeLoop.swift` | 녹음 → 듣기 → 숨 고르기 → 다시 녹음을 정지할 때까지 잇는 순서표, 쉬어 가기 안내 간격(15분) |
| `VoicePractice/Views/PracticeControlsView.swift` | 화면 아래 고정 영역: 지금 단계·시간(쉬는 중에는 안내 문구와 ‘들려줄 길이’ 버튼), 쉬어 가기 안내, 시작·정지·지금 들어보기·건너뛰기·다시 듣기 버튼 |
| `VoicePracticeTests/PracticeLoopTests.swift` | 연습 고리 순서, 최근 N초만 남기는 녹음 통, 다시 듣기 중 그래프 시계를 확인하는 시험지 |
| `VoicePractice/Audio/PitchDetector.swift` | 소리 조각 하나를 받아 "지금 몇 Hz인지" 계산하는 계산기 (YIN 알고리즘) |
| `VoicePractice/Models/PitchHistory.swift` | 피치 기록(점마다 F1·F2도 함께)을 담아 두는 메모장, 시간 구간 꺼내기 |
| `VoicePractice/Models/PracticeSentences.swift` | 직접 쓴 연습 문장 목록. 직접 고쳐도 되는 파일 |
| `VoicePractice/Models/SentencePatterns.swift` | 자동 생성용 문장 틀(패턴)과 단어 목록. 직접 고쳐도 되는 파일 |
| `VoicePractice/Models/SentenceGenerator.swift` | 패턴의 빈칸을 단어로 채우고, 받침에 맞게 조사를 고르고, 말투와 모음이 고르게 15문장을 골라 주는 문장 공장 |
| `VoicePractice/Models/KoreanVowel.swift` | 한글 글자를 분해해서 어떤 단모음(아·어·오·우·으·이·에)이 몇 번 나오는지 세는 도구 |
| `VoicePractice/Models/PracticeDuration.swift` | 연습 시간("지금 들어보기"로 들려줄 최근 길이) 규칙: 10초~3분, 10초 단위, "1분 30초" 같은 표시 문구 |
| `VoicePractice/Models/PracticeScripts.json` | 낭독 대본 200편. 직접 고치거나 추가해도 되는 파일 (고친 뒤 ⌘U로 검사) |
| `VoicePractice/Models/PracticeScript.swift` | 대본 파일을 읽고, 음절 수로 예상 낭독 시간을 계산하는 도구 |
| `VoicePractice/Views/ScriptReaderView.swift` | 대본을 고르고 스크롤해서 읽는 화면 조각 |
| `VoicePractice/Views/KoreanLineBreaking.swift` | 한글 문장이 단어 중간이 아니라 띄어쓰기에서 줄바꿈되게 하는 도구 |
| `VoicePracticeTests/PracticeScriptTests.swift` | 대본 200편의 길이·금지어·숫자·중복과 꺾은선 끊기 규칙을 확인하는 시험지 |
| `VoicePractice/Views/PitchGraphView.swift` | 현재 Hz 숫자, 10초 그래프(반음 눈금), 목표 범위 띠와 슬라이더, 기준 목소리 점선, 내 목소리 재기 버튼을 그리는 화면 조각 |
| `VoicePractice/Models/PitchScale.swift` | 반음 눈금 계산: 두 높이의 반음 거리, 반음만큼 옮기기, 그래프 위치(로그 눈금), 눈금 숫자 고르기 |
| `VoicePracticeTests/PitchScaleTests.swift` | 반음 계산·위치·같은 반음 = 같은 길이·눈금을 확인하는 시험지 |
| `VoicePractice/Views/SentenceCardView.swift` | 연습 문장을 카드로 보여 주고 넘기는 화면 조각. 내 문장/자동 생성 전환 포함 |
| `VoicePractice/Views/PracticeDurationView.swift` | ‘들려줄 길이’(예전 이름 연습 시간) 작은 버튼과, 누르면 뜨는 슬라이더 창 |
| `VoicePractice/Views/PermissionDeniedView.swift` | 마이크 권한이 꺼졌을 때 켜는 방법을 알려 주는 화면 |
| `VoicePractice/Assets.xcassets` | 앱 아이콘(`AppIcon.appiconset/AppIcon.png`, 1024×1024)과 색 세트(AccentColor 파랑, UllimPink, UllimPurple, UllimGreen — 밝은·어두운 모드 값, UllimPurpleFill — 흰 글자가 얹히는 보라 버튼용) |
| `VoicePractice/Views/UllimTheme.swift` | 울림 색의 역할 이름(`UllimColor`): 목소리 분홍, 목표·강조 파랑, 내 기준 보라, 기록 초록 |
| `VoicePracticeTests/UllimThemeTests.swift` | 색 대비(글자 4.5:1)와 어두운 모드가 아이콘 색 그대로인지 확인하는 시험지 |
| `VoicePracticeTests/PitchDetectorTests.swift` | 가짜 소리(사인파·잡음)를 넣어 피치 계산이 맞는지, 모음 세기가 맞는지 자동으로 확인하는 시험지 |
| `VoicePracticeTests/SentenceGeneratorTests.swift` | 조사·말투·중복·모음 균형과 패턴 오타, 연습 시간 규칙을 확인하는 시험지. 패턴을 고친 뒤 ⌘U로 돌려 보면 된다 |
| `Tools/PitchValidation/main.swift` | 앱의 피치 계산기를 녹음 파일에 돌려 Praat 결과와 비교하는 검사 도구. 앱에는 들어가지 않는다 |
| `Tools/PitchValidation/plot.py` | 검사 결과를 그림으로 그리는 스크립트 |
| `Validation/YIN_vs_Praat.md`, `Validation/figures/` | 검증 보고서와 그림. **본인 피치 자료가 들어 있어 GitHub에 올리지 않는다** (`.gitignore`) |
| `Docs/script_samples.md` | 대본 샘플 10개 (확인용) |
| `VoicePractice.xcodeproj` | Xcode가 여는 프로젝트 파일. 어떤 파일을 어떻게 빌드할지 적혀 있다 |
| `VoicePractice-Info.plist` | 빌드 설정으로 넣을 수 없는 앱 정보. 지금은 "오디오 파일을 열 수 있는 앱" 등록만 들어 있다 |
| `Signing.xcconfig` | 서명 설정의 기본값(자리표시자 번들 ID). 실제 값은 깃에 올리지 않는 `Signing.local.xcconfig`에서 읽는다 |
| `CLAUDE.md` | 이 프로젝트의 원칙과 작업 규칙 (Claude가 매번 먼저 읽는다) |
| `PROGRESS.md` | 지금 상태 한 단락, 다음 할 일, 알려진 문제 (짧게 유지) |
| `README.md` | 저장소 첫 화면: 앱 소개, 원칙, 검증 결과, 빌드 방법 |
| `Docs/CHANGELOG.md` | 날짜별 작업 기록 (오래된 것부터) |
| `Docs/FILES.md` | 지금 이 파일. 무엇을 하는 파일인지 한 줄씩 |
| `Docs/DEVICE_TEST.md` | 아이폰에서 직접 확인할 목록 (화면 순서대로, 약 35분) |
| `Docs/screenshots/` | README에 붙인 화면 캡처 (시뮬레이터, 합성음·가짜 기록) |
