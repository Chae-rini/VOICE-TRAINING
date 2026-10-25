import SwiftUI

/// 남긴 녹음 하나: 요약 수치, 메모·언어 고치기, 다시 듣기([높이] 탭에서 곡선과 함께), 지우기.
struct RecordingDetailView: View {
    @Bindable var recording: SavedRecording
    let archive: PracticeArchive
    /// 연습 중이거나 파일을 분석하는 중이면 다시 듣기를 막는다.
    let canPlay: Bool
    /// [높이] 탭으로 가서 이 녹음을 재생한다.
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    /// 화면이 닫힌 뒤에 지운다. 보고 있는 동안 지우면 화면이 지워진 기록을 읽으려다 멈출 수 있다.
    @State private var deleteOnDisappear = false

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: archive.fileURL(for: recording).path)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("남긴 때", value: recording.recordedAt.formatted(.dateTime.year().month().day().weekday().hour().minute()))
                LabeledContent("길이", value: PitchSummary.durationLabel(recording.durationSeconds))
                Picker("말한 언어", selection: $recording.languageCode) {
                    ForEach(PracticeLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
            }

            Section("높이") {
                LabeledContent("중앙", value: "\(Int(recording.medianHz.rounded())) Hz")
                LabeledContent("범위 (아래 10%~위 10%)", value: "\(Int(recording.lowHz.rounded()))–\(Int(recording.highHz.rounded())) Hz")
                if let target = recording.target {
                    LabeledContent("그때 목표 범위", value: "\(Int(target.lowerBound))–\(Int(target.upperBound)) Hz")
                    LabeledContent("목표 범위 안", value: recording.inTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                } else {
                    LabeledContent("그때 목표 범위", value: "정하지 않음")
                }
            }

            Section("메모") {
                TextField("어떤 연습이었는지 적어 두세요", text: $recording.memo, axis: .vertical)
                    .lineLimit(1...5)
            }

            Section {
                Button {
                    onPlay()
                } label: {
                    Label("다시 듣고 곡선 보기", systemImage: "play.fill")
                }
                .disabled(!canPlay || !fileExists)
            } footer: {
                if !fileExists {
                    Text("소리 파일을 찾을 수 없어요. 숫자 기록만 남아 있어요.")
                } else if !canPlay {
                    Text("연습을 멈춘 뒤에 들을 수 있어요.")
                } else {
                    Text("[높이] 탭으로 가서 재생하며 그때의 곡선을 다시 그려요.")
                }
            }

            Section {
                Button("이 녹음 지우기", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .navigationTitle(recording.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("이 녹음을 지울까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                deleteOnDisappear = true
                dismiss()
            }
        } message: {
            Text("소리 파일과 요약, 메모가 이 기기에서 지워져요. 되돌릴 수 없어요.")
        }
        .onDisappear {
            if deleteOnDisappear {
                archive.delete(recording)
            } else {
                archive.save()  // 고친 메모·언어
            }
        }
    }
}
