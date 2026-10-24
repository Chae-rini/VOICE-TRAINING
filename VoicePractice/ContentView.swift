import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var audio = AudioInputManager()
    @AppStorage("practiceDurationSeconds") private var practiceDuration = PracticeDuration.defaultSeconds
    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @AppStorage(TargetRangeStore.baselineMedianKey) private var baselineMedian: Double?
    @AppStorage(TargetRangeStore.baselinePromptShownKey) private var baselinePromptShown = false
    @AppStorage(PracticeLanguage.storageKey) private var language = PracticeLanguage.korean
    @Environment(\.scenePhase) private var scenePhase

    @State private var isImporting = false
    /// 파일 고르기 창을 무엇에 쓰는지. 파일 고르기 창은 화면에 하나만 두고 용도만 바꾼다.
    @State private var importPurpose = ImportPurpose.recording
    @State private var sharePayload: SharePayload?
    @State private var isMeasuringBaseline = false

    private enum ImportPurpose {
        /// 녹음을 불러와 재생하며 보기
        case recording
        /// 내 모음 지도에 모음 하나로 재기
        case vowel(KoreanVowel)
    }

    /// 공유 창에 넘길 것: 피드백 요청문과 녹음 파일
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    var body: some View {
        Group {
            if audio.permission == .denied {
                PermissionDeniedView()
            } else {
                // 아래 탭: [높이] 피치 연습, [모음] 모음 지도. 녹음·듣기 조작은 두 탭이 같은 것을 쓴다.
                TabView {
                    practiceScreen
                        .tabItem { Label("높이", systemImage: "waveform.path") }
                    VowelMapScreen(audio: audio, caption: vowelCaption) { vowel in
                        importPurpose = .vowel(vowel)
                        isImporting = true
                    }
                    .safeAreaInset(edge: .bottom) { controls }
                        .tabItem { Label("모음", systemImage: "mouth") }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                audio.refreshPermission()
            case .background:
                // 백그라운드에서는 마이크와 스피커를 쓰지 않는다.
                audio.stop()
            default:
                break
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: audio.finishedTakeCount)
        .sensoryFeedback(.impact(weight: .heavy), trigger: audio.restReminderCount)
        // 음성 메모는 공유 → "파일에 저장"을 해 두면 여기서 고를 수 있다.
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            switch importPurpose {
            case .recording:
                Task { await audio.importRecording(from: url) }
            case .vowel(let vowel):
                Task { await audio.measureVowel(vowel, fromFile: url) }
            }
        }
        // 음성 메모 등의 공유 창에서 이 앱을 고르면, iOS가 파일을 앱 안에 복사해 넘겨준다.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            Task { await audio.openSharedRecording(url) }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items) {
                sharePayload = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var practiceScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                PitchGraphView(
                    history: audio.history,
                    currentFrequency: audio.currentFrequency,
                    clock: audio.graphClock,
                    caption: graphCaption,
                    canMeasure: !audio.isRunning && !audio.isAnalyzingFile
                ) {
                    isMeasuringBaseline = true
                }

                if let summary, let title = audio.lastTakeTitle {
                    RecordingSummaryView(
                        title: title, summary: summary, isSaved: audio.lastTakeIsSaved, isSaving: audio.isSavingTake,
                        onSave: { memo in
                            Task { await audio.saveLastTake(summary: summary, memo: memo, language: language) }
                        },
                        onShare: { includesAudio in
                            share(summary: summary, title: title, includesAudio: includesAudio)
                        }
                    )
                }

                languageRow

                SentenceCardView(isPracticing: audio.isRunning)
            }
            .padding()
        }
        // 시작 버튼은 스크롤과 상관없이 항상 화면 아래에 보이게 한다.
        .safeAreaInset(edge: .bottom) { controls }
        .sheet(isPresented: $isMeasuringBaseline, onDismiss: {
            // 끌어내려 닫았을 때도 재기를 멈추고 결과를 지운다.
            if audio.loop.phase == .measuring {
                audio.stop()
            }
            audio.clearMeasurement()
        }) {
            BaselineMeasureView(audio: audio)
        }
        .onAppear {
            // 처음 실행할 때 한 번: 기준 목소리를 아직 안 쟀으면 재기 화면을 띄운다 ("나중에"로 건너뛸 수 있음).
            if baselineMedian == nil, !baselinePromptShown {
                baselinePromptShown = true
                isMeasuringBaseline = true
            }
        }
    }

    /// 화면 아래 고정 영역 (두 탭이 함께 쓴다)
    private var controls: some View {
        PracticeControlsView(audio: audio, practiceDuration: $practiceDuration, language: language) {
            importPurpose = .recording
            isImporting = true
        }
    }

    /// 연습할 때 말하는 언어. 기록에 함께 남아, 나중에 언어별로 높이를 비교할 수 있다. 연습 중에는 바꾸지 않는다.
    private var languageRow: some View {
        HStack {
            Label("말하는 언어", systemImage: "globe")
            Spacer()
            Picker("말하는 언어", selection: $language) {
                ForEach(PracticeLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.menu)
            .disabled(audio.isRunning)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
    }

    private var vowelCaption: String {
        switch audio.loop.phase {
        case .recording: "지금 내는 모음"
        case .listening, .replaying: "녹음을 다시 듣는 중"
        case .countdown: "곧 다시 녹음해요"
        case .measuring: audio.measuringVowel.map { "‘\($0.rawValue)’ 길게 내는 중" } ?? "내 목소리 재는 중"
        case .idle:
            audio.hasLastTake ? "마지막 녹음" : "‘반복 루프 재생’을 누르고 모음을 길게 내 보세요"
        }
    }

    /// 마지막 녹음의 피치 요약. 녹음하는 동안에는 숨긴다.
    private var summary: PitchSummary? {
        guard audio.hasLastTake, let duration = audio.lastTakeDuration else { return nil }
        if case .recording = audio.loop.phase { return nil }
        var target: ClosedRange<Double>?
        if let targetLower, let targetUpper {
            target = min(targetLower, targetUpper)...max(targetLower, targetUpper)
        }
        return PitchSummary(readings: audio.history.readings, duration: duration, target: target)
    }

    private func share(summary: PitchSummary, title: String, includesAudio: Bool) {
        // 파일을 못 만들면 요청문만이라도 넘긴다.
        let file = includesAudio ? (try? audio.exportLastTake()) : nil
        let request = summary.feedbackRequest(title: title, includesAudio: file != nil)
        if let file {
            sharePayload = SharePayload(items: [request, file])
        } else {
            sharePayload = SharePayload(items: [request])
        }
    }

    private var graphCaption: String {
        switch audio.loop.phase {
        case .recording: "현재 목소리 높이"
        case .listening, .replaying: "녹음을 다시 듣는 중"
        case .countdown: "곧 다시 녹음해요"
        case .measuring: audio.measuringVowel.map { "‘\($0.rawValue)’ 길게 내는 중" } ?? "내 목소리 재는 중"
        case .idle:
            audio.hasLastTake ? "마지막 녹음" : "‘반복 루프 재생’을 누르면 녹음과 분석을 시작해요"
        }
    }
}

#Preview {
    ContentView()
}
