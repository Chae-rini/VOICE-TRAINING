import SwiftUI

/// 화면 아래 고정 영역: 연습 시간, 지금 단계와 시간, 단계별 버튼.
///
/// 버튼은 단계마다 바뀐다.
/// - 쉬는 중: [녹음 불러오기] [▶ 마지막 녹음] [반복 루프 재생] → 정지할 때까지 녹음이 이어진다
/// - 녹음 중: [정지] [지금 들어보기] → 최근 녹음을 들려주고, 끝나면 자동으로 다시 녹음
/// - 듣는 중: [정지] [건너뛰기]
struct PracticeControlsView: View {
    let audio: AudioInputManager
    /// "지금 들어보기"를 누르면 들려줄 최근 길이 [s]
    @Binding var practiceDuration: Double
    /// 기록에 함께 남길 연습 언어
    let language: PracticeLanguage
    /// 파일 앱에서 녹음 파일을 고르는 창을 연다.
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            PracticeDurationView(seconds: $practiceDuration, isLocked: audio.isRunning)

            status

            if let message = audio.restMessage {
                Label(message, systemImage: "cup.and.saucer")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                switch audio.loop.phase {
                case .idle:
                    Button(action: onImport) {
                        Label("녹음 불러오기", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(audio.isAnalyzingFile)

                    if audio.hasLastTake {
                        Button {
                            audio.replayLastTake()
                        } label: {
                            Label("마지막 녹음 듣기", systemImage: "play.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    mainButton("반복 루프 재생", systemImage: "repeat") {
                        let duration = PracticeDuration.normalized(practiceDuration)
                        Task { await audio.start(duration: duration, language: language) }
                    }
                    .disabled(audio.isAnalyzingFile)
                case .recording:
                    stopButton
                    mainButton("지금 들어보기", systemImage: "play.fill") {
                        audio.listenNow()
                    }
                case .listening:
                    stopButton
                    mainButton("건너뛰기", systemImage: "forward.fill") {
                        audio.skipListening()
                    }
                case .countdown, .replaying, .measuring:
                    stopButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func mainButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            audio.stop()
        } label: {
            Label("정지", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
    }

    /// 지금 단계와 시간(녹음은 녹음한 시간, 나머지는 남은 시간). 연습 중이 아니면 안내·오류 문구.
    @ViewBuilder
    private var status: some View {
        switch audio.loop.phase {
        case .recording(let round):
            phaseRow(icon: "record.circle", tint: .red, text: "녹음 중 · \(round)번째")
        case .listening(let round):
            phaseRow(icon: "speaker.wave.2.fill", tint: .teal, text: "방금 녹음 듣는 중 · \(round)번째")
        case .countdown(let nextRound):
            phaseRow(icon: "pause.circle", tint: .secondary, text: "숨 고르기 · 곧 \(nextRound)번째 녹음")
        case .replaying:
            phaseRow(icon: "speaker.wave.2.fill", tint: .teal, text: "‘\(audio.lastTakeTitle ?? "마지막 녹음")’ 듣는 중")
        case .measuring:
            phaseRow(icon: "waveform", tint: .indigo,
                     text: audio.measuringVowel.map { "‘\($0.rawValue)’ 길게 내는 중" } ?? "내 목소리 재는 중")
        case .idle:
            if audio.isAnalyzingFile {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("녹음을 분석하는 중…")
                }
                .font(.subheadline)
            } else if let message = audio.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let message = audio.infoMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.teal)
            }
        }
    }

    private func phaseRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
            Spacer()
            Group {
                if let start = audio.recordingStart {
                    // 녹음한 시간이 1초마다 늘어난다.
                    Text(start, style: .timer)
                } else if let interval = audio.phaseInterval {
                    // 남은 시간이 1초마다 줄어든다.
                    Text(timerInterval: interval, countsDown: true)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
