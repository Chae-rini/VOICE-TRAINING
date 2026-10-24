import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var audio = AudioInputManager()
    @AppStorage("practiceDurationSeconds") private var practiceDuration = PracticeDuration.defaultSeconds
    @AppStorage("targetLowerHz") private var targetLower = 180.0
    @AppStorage("targetUpperHz") private var targetUpper = 220.0
    @Environment(\.scenePhase) private var scenePhase

    @State private var isImporting = false
    @State private var sharePayload: SharePayload?

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
                practiceScreen
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
        .sensoryFeedback(.success, trigger: audio.completedPracticeCount)
        // 음성 메모는 공유 → "파일에 저장"을 해 두면 여기서 고를 수 있다.
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await audio.importRecording(from: url) }
            }
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
                    caption: graphCaption
                )

                if let summary, let title = audio.lastTakeTitle {
                    RecordingSummaryView(title: title, summary: summary) { includesAudio in
                        share(summary: summary, title: title, includesAudio: includesAudio)
                    }
                }

                SentenceCardView(isPracticing: audio.isRunning)
            }
            .padding()
        }
        // 시작 버튼은 스크롤과 상관없이 항상 화면 아래에 보이게 한다.
        .safeAreaInset(edge: .bottom) {
            PracticeControlsView(audio: audio, practiceDuration: $practiceDuration) {
                isImporting = true
            }
        }
    }

    /// 마지막 녹음의 피치 요약. 녹음하는 동안에는 숨긴다.
    private var summary: PitchSummary? {
        guard audio.hasLastTake, let duration = audio.lastTakeDuration else { return nil }
        if case .recording = audio.loop.phase { return nil }
        let target = min(targetLower, targetUpper)...max(targetLower, targetUpper)
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
        case .idle, .finished:
            audio.hasLastTake ? "마지막 녹음" : "‘반복 루프 재생’을 누르면 녹음과 분석을 시작해요"
        }
    }
}

#Preview {
    ContentView()
}
