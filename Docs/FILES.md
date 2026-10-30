# 파일 안내 (무엇을 하는 파일인지 한 줄씩)

| 파일 | 하는 일 |
|---|---|
| `VoicePractice/VoicePracticeApp.swift` | 앱의 시작점. 앱이 켜지면 첫 화면(ContentView)을 띄우고, 기록 저장소를 화면에 연결한다 |
| `VoicePractice/ContentView.swift` | 첫 화면. 권한이 꺼져 있으면 안내 화면을, 아니면 [높이]·[모음] 탭과 아래 고정된 연습 조작 영역, 말하는 언어 고르기를 보여준다 |
| `VoicePractice/Audio/AudioInputManager.swift` | 마이크·스피커 담당. 연습 고리 순서대로 녹음하고, 들어온 소리를 피치 검출기에 넘기고, 방금 녹음을 들려준다. 정지하면 연습 요약을 기록에 남기고, ‘기록에 남기기’를 누르면 녹음을 저장소에 넘긴다 |
| `VoicePractice/Audio/TakeRecorder.swift` | 녹음 중 들어온 소리 중 최근 N초만 메모리에 남기는 고리 모양 통 (다시 듣기용) |
| `VoicePractice/Audio/AudioFileAnalyzer.swift` | 녹음 파일(음성 메모 등)을 읽어 피치를 미리 계산하고, 공유용 WAV·기록용 m4a 파일을 만드는 도구 |
| `VoicePractice/Models/PitchSummary.swift` | 녹음의 요약 수치(중앙값·범위·목표 범위 안 비율)와 AI에게 보낼 피드백 요청문 |
| `VoicePractice/Models/PhraseEndingAnalysis.swift` | 구절별 문장 끝 분석: 무성음 250 ms로 구절을 나누고, 구절마다 끝 300 ms가 몇 반음 내려갔는지·끝 바닥·긁히는 소리 가능성, 녹음 전체 요약 (화면과 상관없는 계산만) |
| `VoicePractice/Models/PhraseEndingRules.json` | 문장 끝 분석의 기준값(구절 나누기·끝 길이·하강 폭 경계·fry 기준). iOS와 웹이 이 파일 하나를 같이 읽는다. 값마다 뜻을 `notes`에 적었다 |
| `VoicePractice/Views/RecordingSummaryView.swift` | 그래프 아래 요약 카드와 "기록에 남기기"(메모 창)·"AI에게 피드백 받기"·"요약 복사" 버튼, iOS 공유 창. 숫자 아래에 문장 끝 칸 |
| `VoicePractice/Views/PhraseEndingListView.swift` | 요약 카드 안의 문장 끝 칸: 요약 한 줄·숫자·안내 문구, 펼치면 구절 목록(화살표·종류·중앙값 → 끝 Hz·하강 반음), 종류별 색 |
| `VoicePractice/Models/PhraseEndingText.swift` | 문장 끝 분석을 글로 바꾸기: 요약 한 줄, 숫자 줄, 안내 문구, AI 요청문 단락, 구절 한 줄 (웹 `text/phraseEnding.ts`와 같은 글) |
| `VoicePractice/Models/PracticeRecord.swift` | 기록의 모양: 말하는 언어, 연습 한 번 모으기 규칙(30초·5초 기준), 저장하는 기록 4가지(연습 요약, 남긴 녹음, 기준 목소리 이력, 모음 이력) |
| `VoicePractice/Models/PracticeArchive.swift` | 기록 저장소: 숫자는 SwiftData, 남긴 녹음은 m4a 파일(백업 제외). 저장·하나 지우기·모두 지우기를 한곳에서 하고, 저장에 실패하면 되돌린 뒤 오류를 알린다 |
| `VoicePractice/Models/RecordedTake.swift` | 녹음 한 번의 묶음: 소리, 시작 시각·길이, 그 구간의 피치·포먼트 점, 남긴 기록의 ID. 요약·저장·공유·다시 듣기는 이것만 쓴다 |
| `VoicePractice/Models/RecordingTimeline.swift` | 녹음·재기 중의 피치 점을 화면 그래프용·재기용으로 나눠 담고, 마지막 녹음 묶음을 들고 있는 곳 |
| `VoicePracticeTests/RecordedTakeTests.swift` | 외부 리뷰 버그 세 개(요약 구간, 재기 덮어쓰기, 저장 실패)의 재현 테스트 |
| `VoicePracticeTests/StoppedTakeTests.swift` | 정지로 끊은 빈 녹음이 그 전 녹음을 덮어쓰지 않는지 (목소리 0.5초 기준, ‘지금 들어보기’는 그대로) |
| `VoicePracticeTests/PhraseEndingRecordTests.swift` | 기록에 남긴 문장 끝 숫자: 연습 기록·남긴 녹음 저장·되읽기, 예전 기록(빈 칸), 녹음 여러 개 합치기, 연습 기록 요청문 |
| `VoicePracticeTests/PracticeRecordTests.swift` | 연습 한 번 모으기 규칙과 저장소(저장·다시 읽기·m4a·백업 제외·하나 지우기·모두 지우기·녹음 이름)를 확인하는 시험지 |
| `VoicePractice/Models/PracticeHistory.swift` | [기록] 탭의 계산 규칙: 기간(7일·30일·전체), 언어 거르기, 날마다 연습 시간, 모아 보기, 그래프 축 범위(높이·공명 밝기 F2), 시간 표시 |
| `VoicePractice/Models/SampleHistory.swift` | 개발용 가짜 기록 40일치 (시뮬레이터 확인용, Debug 빌드에서 `-seedSampleHistory YES`일 때만). 30일 전부터는 F2도 |
| `VoicePractice/Views/HistoryScreen.swift` | [기록] 탭 화면: 기간·언어 고르기, 모아 보기, 그래프, 남긴 녹음·연습 기록·내 목소리 재기 목록, 모든 기록 지우기 |
| `VoicePractice/Views/HistoryChartView.swift` | [기록] 탭의 그래프 세 개 (연습마다 높이, 연습마다 공명 밝기 F2, 날마다 연습 시간). Swift Charts |
| `VoicePractice/Views/PracticeSessionDetailView.swift` | 연습 기록 자세히: 연습 전체·녹음마다의 숫자, AI에게 보낼 요약 글(공유·복사) |
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
| `VoicePractice/Models/VoiceBaseline.swift` | 내 기준 목소리 계산(중앙값·범위·목소리 안 잡힘·공명 밝기 기준 F2), 처음 목표 범위(±20 Hz), 반음 거리, 목표 범위·기준 저장 규칙(예전 사용자 값 지키기) |
| `VoicePractice/Models/BaselineReading.swift` | 내 목소리 재기에서 읽을 글: 내 문장 + 평소 말투 대본(대화문·독백·비문학·수필, 사실 확인된 것) 중 무작위, 직전 글 빼기, 안내 글 |
| `VoicePractice/Views/BaselineMeasureView.swift` | "내 목소리 재기" 화면: 무작위로 고른 문장·대본을 읽고 10초 재기(‘다른 대본’으로 바꾸기) 또는 녹음 파일로 재기, 결과와 목표 범위 맞추기 스위치 |
| `VoicePracticeTests/VoiceBaselineTests.swift` | 기준 계산·처음 목표 범위·저장값 유지·목소리 안 잡힘·파일로 재기를 확인하는 시험지 |
| `VoicePracticeTests/BaselineReadingTests.swift` | 재기에서 읽을 글: 후보 범위, 직전 글 빼기, 같은 시드면 같은 글, 후보가 적을 때, 안내 글 |
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
| `VoicePractice/Views/PitchGraphView.swift` | [높이] 위에 고정되는 현재 Hz 숫자와 피치 그래프(반음 눈금, 가로축 = 들려줄 길이, 시간 눈금, 시작·n번째 선, 재생 위치 선, 대본 읽기 모드)와 그 아래 음량·공명 밝기 막대. 같은 파일의 `MeterGuideView`는 막대 보는 법, `TargetRangeControls`는 목표 범위 줄·슬라이더·내 목소리 재기 버튼 |
| `VoicePractice/Views/AudioFileDocument.swift` | ‘파일로 저장’에서 iOS 파일 저장 창에 넘기는 m4a 파일과 처음 파일 이름(Ullim-날짜-시각) |
| `VoicePracticeTests/AudioFileExportTests.swift` | 파일 이름·확장자(.m4a), 마지막 녹음 m4a 만들기·다시 재기·임시 파일 정리, 그래프 높이를 확인하는 시험지 |
| `VoicePractice/Models/VoiceMeters.swift` | [높이] 탭 음량 막대(dBFS, 0.3초 평활, 큰 소리 3초 지속 판정)와 공명 밝기 막대(최근 2.5초 F2 중앙값, 기준 대비 위치) 계산 |
| `VoicePracticeTests/VoiceMetersTests.swift` | 음량·평활·큰 소리 판정, F2 이동 중앙값, 기준 대비 위치, F2 저장을 확인하는 시험지 |
| `VoicePracticeTests/PhraseEndingAnalysisTests.swift` | 구절별 문장 끝 분석의 시험지: 기준값 파일, 종류 경계, fry 연속 기준 환산, 합성 피치 9가지 (웹 테스트와 같은 입력 파일) |
| `VoicePracticeTests/PhraseEndingCases.json` | 문장 끝 분석의 합성 피치 입력과 손으로 셈한 기대값. iOS·웹 테스트가 같이 읽는다. `Tools/PhraseEndingCases/make_cases.py`가 만들므로 손으로 고치지 않는다 |
| `VoicePractice/Models/GraphWindow.swift` | 피치 그래프 가로축 계산: 보이는 시간 구간(오른쪽 끝 = 지금), 시간 눈금 간격·글자, 시작선 |
| `VoicePracticeTests/GraphWindowTests.swift` | 그래프 구간·시간 눈금·시작선·점 묶기를 확인하는 시험지 |
| `VoicePractice/Models/PitchScale.swift` | 반음 눈금 계산: 두 높이의 반음 거리, 반음만큼 옮기기, 그래프 위치(로그 눈금), [높이] 세로축 범위(목표 ±50 Hz)와 축 밖 판정, 눈금 숫자 고르기(높이·공명 밝기 F2) |
| `VoicePracticeTests/PitchScaleTests.swift` | 반음 계산·위치·같은 반음 = 같은 길이·세로축 범위·축 밖 판정·눈금을 확인하는 시험지 |
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
| `Tools/WebGolden/main.swift` | 앱의 피치·포먼트 계산기에 합성 신호를 넣어 웹 버전이 비교할 정답표(`web/test/golden/swift-golden.json`)를 만드는 도구. 앱에는 들어가지 않는다 |
| `Tools/PhraseEndingCases/make_cases.py` | 문장 끝 분석의 테스트 입력 파일(`VoicePracticeTests/PhraseEndingCases.json`)을 만드는 스크립트. 경우마다 기대값을 어떻게 셈했는지 주석에 있다 |
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
| `Docs/WEB_PLAN.md` | 웹(PWA)·안드로이드(APK) 계획: 정한 것, 단계(W0~W5, A1·A2)와 상태, iOS와 다른 점 |
| `web/package.json`, `web/package-lock.json` | 웹 버전이 쓰는 도구와 정확한 버전, 명령(`dev`·`build`·`test`·`check`) |
| `web/vite.config.ts`, `web/tsconfig.json` | 웹 빌드·테스트 설정 (상대 경로로 빌드: GitHub Pages·APK 어디서나 열리게). 개발 서버가 내줄 파일을 `web/`과 대본 JSON으로 좁히고, `dev:lan`일 때만 와이파이에 HTTPS로 연다 |
| `web/index.html` | 웹 첫 페이지. 앱 자신의 파일 말고는 연결하지 못하게 막는 CSP (원칙 2) |
| `web/capacitor.config.ts` | 안드로이드 앱(APK) 설정: 앱 ID·이름·웹 빌드 위치. 원격 주소는 쓰지 않는다 |
| `web/android/` | Capacitor가 만든 안드로이드 프로젝트. 고친 곳: `app/src/main/AndroidManifest.xml`(마이크·저장 권한, 평문 통신 끄기), `app/build.gradle`(아래), `app/src/main/res/`의 아이콘·시작 화면 그림, 테마 아이콘 단색 층 `drawable/ic_launcher_monochrome.xml`(손으로 그린 선 그림), 다크 모드 시작 화면 바탕 `values-night/styles.xml` |
| `web/scripts/gradle.sh` | 안드로이드 빌드 도구(Gradle)를 JDK 21·Android Studio SDK로 돌리는 스크립트 (`npm run apk:debug`·`apk:release`가 쓴다) |
| `web/scripts/android-icons.sh` | iOS 앱 아이콘 하나로 안드로이드 아이콘(예전용·모양 맞춤)과 시작 화면 그림을 만드는 스크립트 |
| `web/android/app/build.gradle` | 안드로이드 앱 빌드 설정: 버전(versionCode·versionName), 완성 APK 서명(저장소 밖 `~/Documents/울림-서명키`를 읽는다) |
| `web/src/platform/app.ts` | 안드로이드 앱 안인지 (`isNativeApp`). 앱이면 저장·공유를 앱 기능으로 바꾼다 |
| `web/src/platform/nativeShare.ts` | 앱에서 파일로 저장(‘문서/울림/내보낸 파일’)과 안드로이드 공유 창으로 보내기 |
| `web/src/platform/nativeApp.ts` | 앱을 휴대폰 앱처럼: `html.app` 스타일·확대 막기, 뒤로 버튼(열린 창 → 화면 조각 → [높이] → 앱 뒤로 보내기), 화면이 가려지면 연습 정지 |
| `web/src/platform/backButton.ts` | 뒤로 버튼을 먼저 받는 화면 조각 목록(`onBack`, 나중에 건 것부터)과 열린 창 닫기 |
| `web/src/platform/haptics.ts` | 짧은 진동(앱에서만): 녹음이 끝날 때 약하게, 쉬어 가기 안내 때 강하게 |
| `web/test/backButton.test.ts` | 뒤로 버튼 처리 순서와 열린 창 닫기 시험지 |
| `web/test/stoppedTake.test.ts` | 정지로 끊은 빈 녹음 규칙 시험지 (iOS `StoppedTakeTests`와 같은 기준) |
| `web/src/storage/nativeFolder.ts` | 앱의 기록 폴더(휴대폰의 ‘문서/울림’): 웹 기록 폴더와 같은 읽기·쓰기·지우기·목록, base64로 나눠 쓰기, 저장 권한 |
| `web/test/nativeFolder.test.ts` | 앱 기록 폴더 시험지 (Capacitor 파일 시스템처럼 동작하는 가짜로) |
| `web/src/main.ts`, `web/src/App.svelte`, `web/src/app.css` | 웹 화면 시작점과 공통 모양. App은 화면 셋([높이]·[모음]·[기록])을 숨기기만 하며 바꾸고(문장 위치·스크롤 유지), 그 아래 연습 조작과 탭 막대. 색은 iOS 색 세트와 같은 값(밝은·어두운 모드) |
| `web/src/components/TabBar.svelte`, `navigation.svelte.ts` | 아래 탭 막대(높이·모음·기록)와 화면끼리 함께 보는 상태(지금 탭, 내 목소리 재기 창이 열렸는지) |
| `web/src/components/PracticeControls.svelte` | 화면 아래 연습 조작: 단계 표시·남은 시간, 반복 루프 재생·지금 들어보기·건너뛰기·정지, 녹음 불러오기, 마지막 녹음 듣기, 들려줄 길이. [높이]·[모음]이 함께 쓴다 |
| `web/src/components/PitchScreen.svelte` | [높이] 화면 배치: 위에 고정된 높이·그래프, 스크롤되는 목표 범위·요약·문장. 처음 열 때 내 목소리 재기 |
| `web/src/components/VowelScreen.svelte` | [모음] 화면: 모음 지도, 내 모음 지도(모음 고르기, 3초 재기, 파일로 재기, 잰 결과 안내), 보는 법 |
| `web/src/components/VowelChart.svelte` | 모음 지도 위의 F1·F2 숫자와 고른 모음과의 차이, 지도(캔버스). 재는 동안은 재는 소리, 다시 들을 때는 재생 위치를 따라간다 |
| `web/src/graph/vowelChart.ts` | 모음 지도 그리기(눈금·방향 안내·내 모음 원과 흔들림 십자·꼬리·지금 점), 차이 글자, 화면 읽기 설명 |
| `web/src/model/vowelMap.ts` | 내 모음 지도: 모음 하나 재기(중앙값·25~75% 흔들림·F1 불확실), 저장한 값 읽기(망가진 항목은 빼고) |
| `web/src/components/LivePanel.svelte` | 지금 높이 숫자, 그래프(캔버스), 음량·공명 막대. 화면을 그릴 때마다 최근 점으로 고친다. 화면 읽기 프로그램용 설명 |
| `web/src/components/TargetRangeControls.svelte` | 목표 범위 한 줄·슬라이더(반음 눈금, 5 Hz 단위)·기준에서 먼 범위 안내·내 목소리 재기 버튼 |
| `web/src/components/BaselineSheet.svelte` | 내 목소리 재기 창: 열 때마다 무작위로 고른 문장·대본(‘다른 대본’), 10초 재기, 결과(중앙·범위·F2), 목표 범위를 기준에 맞추기, 저장 |
| `web/src/model/baselineReading.ts` | 내 목소리 재기에서 읽을 글 (iOS `BaselineReading`과 같은 규칙: 내 문장 + 평소 말투 대본, 무작위·직전 글 빼기, 안내 글) |
| `web/test/baselineReading.test.ts` | 재기에서 읽을 글 시험지 (iOS `BaselineReadingTests`와 같은 확인) |
| `web/src/components/SentenceCards.svelte`, `ScriptReader.svelte` | 문장 카드(내 문장·자동 생성, 밀어서 넘기기)와 대본 읽기(종류·길이 거르기, 다른 대본, 들려줄 길이 맞추기) |
| `web/src/components/DurationControl.svelte` | ‘들려줄 길이’ 버튼과 조정 창 (10초~3분) |
| `web/src/practice/session.svelte.ts` | 연습 흐름: 반복 루프(녹음 → 지금 들어보기 → 숨 고르기 → 다시 녹음), 마지막 녹음 다시 듣기, 파일 불러오기, 내 목소리 재기·모음 재기(마이크·파일), 그래프 시계, 15분 쉬어 가기, 정지할 때 연습 기록 남기기, ‘기록에 남기기’ |
| `web/src/practice/loop.ts` | 연습 순서표(지금 어느 단계인지, iOS `PracticeLoop`) |
| `web/src/practice/takeRecorder.ts` | 최근 N초만 남기는 고리 모양 녹음 통 (iOS `TakeRecorder`) |
| `web/src/practice/take.ts` | 녹음 묶음: 소리와 같은 구간의 점만 담고, 요약·F2·가로축·다시 듣기 기록을 낸다 (iOS `RecordedTake`) |
| `web/src/practice/sharing.ts` | 파일로 저장(WAV 내려받기), AI에게 피드백 받기(브라우저 공유 창, 없으면 복사), 요약 복사 |
| `web/src/components/SummaryCard.svelte` | 마지막 녹음 요약 카드: 중앙·범위·목표 범위 안 비율, 문장 끝 칸, 기록에 남기기(메모 창)·파일로 저장·공유·복사 버튼 |
| `web/src/components/PhraseEndingList.svelte` | 요약 카드 안의 문장 끝 칸 (iOS `PhraseEndingSection`) |
| `web/src/text/phraseEnding.ts` | 문장 끝 분석을 글로 바꾸기 (iOS `PhraseEndingText.swift`와 같은 글). 기록에 남은 숫자만으로 쓰는 글(`summary…`)과 녹음 여러 개 합치기(`combinedPhraseSummary`)도 |
| `web/src/graph/pitchGraph.ts` | 그래프 그리기(목표 띠·눈금·기준선·시작선·꺾은선·축 밖 점선·다시 듣기)와 그래프 높이 규칙. 꺾은선 나누기는 순수 함수라 테스트한다 |
| `web/src/graph/descriptions.ts` | 그래프·막대를 말로 바꾼 설명(iOS와 같은 문장), 쉬어 가기 안내 문구 |
| `web/src/model/practice.ts` | 들려줄 길이, 내 기준 목소리 재기·처음 목표 범위·먼 범위 판정, 목표 범위 슬라이더 규칙 |
| `web/src/model/settingsStorage.ts`, `settings.svelte.ts` | 화면 설정(들려줄 길이·문장 종류·대본 거르기·고른 모음)은 이 브라우저(localStorage, `ullim.` 키)에. 내 기준 값(목표 범위·기준·모음 지도)은 화면이 함께 보고 바뀌면 기록 폴더에 알린다. W5까지 브라우저에 있던 내 기준 값을 읽고(옮기기용) 지우기 |
| `web/src/model/records.ts` | `울림-기록.json`에 남는 기록의 모양(연습 기록·녹음마다 요약·남긴 녹음·기준 이력·모음 이력)과 확인, 말하는 언어. 녹음마다·남긴 녹음의 문장 끝 숫자(`phraseEndings`, 없으면 그 전 기록) |
| `web/src/practice/sessionLog.ts` | 연습 한 번의 기록: 녹음마다 요약을 쌓고, 정지하면 30초·목소리 5초 이상일 때 연습 기록 하나로 (iOS `PracticeSessionLog`). 연습 기록의 AI 요청문·녹음 한 줄 |
| `web/src/model/voiceSettings.ts` | 내 기준 값의 모양, 기준을 재면 목표 범위 정하기, 기록 폴더를 열 때 폴더 값과 화면 값 합치기 |
| `web/src/storage/recordStore.svelte.ts` | 내 기록이 남는 곳: 기록 폴더 고르기·다시 연결·바꾸기·끊기, 바뀐 값을 폴더에 쓰기(0.4초 모아서), 기록 더하기(녹음 소리 먼저, 폴더가 없으면 화면에 담아 두었다가 옮김), 기록 파일(zip) 저장·불러오기, 사파리처럼 폴더를 못 고르는 브라우저(개발 서버에서 `?nofolder`로 흉내) |
| `web/src/storage/archive.ts` | 기록 폴더의 파일 모양(`울림-설정.json`·`울림-기록.json`, 판 번호), 읽지 못한 까닭과 안내 문구, 기록 더하기·합치기(id로), 남긴 녹음 파일 이름 |
| `web/src/storage/openFolder.ts` | 기록 폴더 열기(읽기·합치기·빈 폴더면 만들기, 읽지 못하면 아무것도 쓰지 않음), 기록 옮겨 쓰기 |
| `web/src/storage/recordFolder.ts` | 기록 폴더 하나의 읽기·쓰기·지우기·목록: 내가 고른 폴더(파일 시스템 접근 API), 메모리 폴더(사파리·테스트) |
| `web/src/storage/recordZip.ts` | 기록 파일(zip, fflate): 묶기, 풀기(울림 파일만, 폴더째 압축·맥 한글 이름·크기 제한) |
| `web/src/storage/handleStore.ts` | 고른 기록 폴더의 연결 정보를 이 브라우저(IndexedDB)에 기억 |
| `web/src/storage/fileSystemAccess.d.ts` | TypeScript 기본 타입에 아직 없는 폴더 고르기·허락 묻기 타입 |
| `web/src/components/HistoryScreen.svelte` | [기록] 화면: 기간·언어 거르기, 모아 보기, 그래프, 남긴 녹음·연습 기록·내 목소리 재기 목록, 모두 지우기, 저장 위치(필요할 때는 맨 위). 누르면 자세히 화면으로 바뀐다(돌아오면 스크롤 그대로) |
| `web/src/components/HistoryCharts.svelte`, `LanguageTag.svelte` | [기록] 그래프 세 개(연습마다 높이: 반음 눈금·목표 띠·기준 점선·언어별 점 모양 / 연습마다 공명 밝기 F2 / 날마다 연습 시간 막대, SVG)와 언어 표시 |
| `web/src/components/RecordingDetail.svelte`, `SessionDetail.svelte` | 남긴 녹음 자세히(메모·언어 고치기, [높이]에서 다시 듣기, 파일로 저장, 지우기)와 연습 기록 자세히(녹음마다 숫자, AI에게 피드백 받기·요약 복사, 지우기) |
| `web/src/components/StorageCard.svelte` | ‘내 기록 저장 위치’ 카드 |
| `web/src/components/CompareScreen.svelte`, `CompareChart.svelte` | 두 녹음 비교: A·B 고르기(메모 붙임)·바꾸기, 나란히 보기(높낮이 폭 포함)·중앙값 차이 한 문장, 높이 분포(반음 반 칸, SVG), 하나씩·A → B 이어 듣기 |
| `web/src/model/comparison.ts` | 두 녹음 비교의 계산: 처음 짝, 높낮이 폭(반음), 중앙값 차이 글(판정 없음), 반음 반 칸 분포(440 Hz 기준), 분포 가로축 (iOS `RecordingComparison`) |
| `web/src/practice/comparePlayer.svelte.ts` | 두 녹음 비교의 재생기: 남긴 녹음을 읽어 분석하고(늦게 끝난 예전 읽기는 버림), 가장 큰 소리를 맞춰 하나씩·A → 0.7초 → B로 들려준다 |
| `web/src/model/history.ts` | [기록]의 계산: 기간(7일·30일·전체), 거르기, 날마다 연습 시간, 모아 보기, 가로·세로축(높이·공명 밝기 F2, 반음 여유·최소 폭), 시간 표시 (iOS `PracticeHistory`) |
| `web/src/graph/historyChart.ts` | [기록] 그래프 자리: 날짜 위치·날짜 눈금·분 눈금·언어별 점 모양 |
| `web/src/model/sampleHistory.ts` | 개발용 가짜 기록 40일치 (개발 서버 `?seed`, 배포 빌드에는 없음). 30일 전부터는 F2도 |
| `web/src/text/dates.ts` | 날짜·시각 글자 (10월 25일 (일) 오후 8:12 등) |
| `web/src/components/StorageNotice.svelte` | [높이]·[모음] 위의 한 줄 안내(다시 연결, 폴더 고르기, 파일로 저장, 불러오기 안내) |
| `web/src/text/korean.ts`, `sentenceGenerator.ts` | 조사 고르기(을/를 등), 단모음 세기, 자동 생성 문장 (iOS와 같은 규칙) |
| `web/src/data/sentences.ts`, `scripts.ts` | 직접 쓴 문장·패턴·단어(iOS 파일과 같은지 테스트), 대본은 iOS의 `PracticeScripts.json`을 그대로 읽는다 |
| `web/src/dsp/pitchDetector.ts` | YIN 피치 검출 (iOS `PitchDetector.swift`를 그대로 옮김) |
| `web/src/dsp/formantAnalyzer.ts` | LPC 포먼트(F1·F2) 분석 (iOS `FormantAnalyzer.swift`) |
| `web/src/dsp/pitchScale.ts`, `web/src/dsp/range.ts` | 반음 눈금, 세로축 범위(목표 ±50 Hz), 축 밖 판정, 눈금 숫자(높이·공명 밝기 F2) |
| `web/src/dsp/graphWindow.ts` | 가로축 구간(오른쪽 끝 = 지금), 시작·n번째 선, 시간 눈금 |
| `web/src/dsp/pitchHistory.ts` | 피치 점 기록, 끊김·픽셀 열 묶기, 그래프 시계(녹음 중·멈춤·다시 듣기) |
| `web/src/dsp/voiceMeters.ts`, `web/src/dsp/vowelSpace.ts` | 음량(dBFS) 막대, 공명 밝기(F2) 막대, 모음 지도 규칙(F1·F2 범위·눈금·지금 점·위치, F1 불확실) |
| `web/src/dsp/pitchSummary.ts` | 요약 수치(중앙값·10%·90%·목표 안 비율)와 AI 피드백 요청문 |
| `web/src/dsp/phraseEnding.ts` | 구절별 문장 끝 분석 (iOS `PhraseEndingAnalysis.swift`를 줄 단위로 옮김, 기준값은 iOS의 `PhraseEndingRules.json`을 그대로 읽는다) |
| `web/src/dsp/analysis.ts` | 소리 전체를 연습과 같은 방식으로 분석, 다시 듣기 배율, 녹음 묶음에 넣을 점 고르기 |
| `web/src/dsp/streamAnalyzer.ts` | 마이크에서 조각조각 들어오는 소리를 창(2048샘플, 절반씩 밀기)으로 분석 (iOS `PitchTapProcessor`). 조각 크기와 상관없이 파일 분석과 같은 점 |
| `web/src/audio/micInput.ts` | 소리 장치(`AudioEngine`): 소리 시계 하나로 마이크 켜기·녹음 시작·멈추고 소리 받기·다시 듣기 재생·녹음 파일 읽고 분석. 못 켠 까닭별 안내, 개발용 테스트 음·테스트 모음(배음 크기를 공명 모양으로), 개발 서버의 `?mute` |
| `web/src/audio/captureProcessor.ts`, `worklet-globals.d.ts` | 소리 받기(오디오 스레드): 128샘플씩 받아 1024샘플로 모아 분석 스레드로 바로 보낸다 |
| `web/src/audio/analysisWorker.ts` | 분석 스레드: 녹음 중에는 조각을 분석해 점을 보내고 최근 N초를 녹음 통에 남긴다(듣는 동안은 버림). 불러온 녹음 전체 분석 |
| `web/src/audio/wav.ts` | WAV 만들기(16비트 모노), 저장 파일 이름(Ullim-날짜-시각.wav), 여러 채널 합치기·5분 자르기 |
| `web/src/audio/messages.ts` | 소리 받기·분석 스레드·화면이 주고받는 메시지 모양 |
| `web/src/audio/processing.ts` | 브라우저의 자동 음량 조절·잡음 제거·에코 제거를 끄는 조건, 실제로 꺼졌는지 읽어 안내하기 |
| `web/test/*.test.ts` | iOS 테스트를 옮긴 웹 시험지 + `golden.test.ts`(iOS 정답표와 숫자 비교), `streamAnalyzer.test.ts`(조각 분석 = 파일 분석), `processing.test.ts`(자동 처리 안내), `sentences.test.ts`(문장 데이터가 iOS와 같은지, 조사·모음·자동 생성·대본), `practice.test.ts`(들려줄 길이·기준·목표 범위·설정 저장), `graph.test.ts`(그래프 크기·꺾은선 나누기·설명 문장), `loop.test.ts`(연습 순서·녹음 통·녹음 묶음·WAV·내보내기), `vowelMap.test.ts`(모음 지도 규칙·내 모음 지도·저장·지도 글자), `storage.test.ts`(기록 폴더 파일 모양·합치기·열기·옮기기·기록 파일 zip), `records.test.ts`(연습 한 번의 기록·기록 모양·기록 합치기·녹음 파일 이름·말하는 언어), `history.test.ts`([기록] 계산·연습 기록 요청문·그래프 자리·가짜 기록), `comparison.test.ts`(두 녹음 비교 계산) |
| `web/test/signals.ts` | 웹 테스트용 합성 신호 (iOS 테스트·`Tools/WebGolden`과 같은 식) |
| `web/test/golden/swift-golden.json` | `Tools/WebGolden`이 만든 정답표. 손으로 고치지 않는다 |
| `web/test/phraseEnding.test.ts` | 구절별 문장 끝 분석의 시험지 (iOS `PhraseEndingAnalysisTests`와 같은 입력·기대값 파일을 읽는다) |
| `web/test/phraseRecords.test.ts` | 기록에 남긴 문장 끝 숫자: 연습 기록·남긴 녹음 저장·되읽기, 예전 기록·망가진 칸, 녹음 여러 개 합치기, 연습 기록 요청문 (iOS `PhraseEndingRecordTests`와 같은 숫자·같은 글) |
