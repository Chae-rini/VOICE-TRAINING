import SwiftUI
import UIKit

/// 마지막 녹음(방금 녹음 또는 불러온 파일)의 피치 요약 카드.
/// "기록에 남기기"는 이 녹음의 소리와 요약을 기기 안에 저장한다 (누를 때만).
/// "AI에게 피드백 받기"는 요약(원하면 녹음 파일도)을 iOS 공유 창에 넘기고, 보낼 앱은 사용자가 고른다.
/// "파일로 저장"은 녹음을 m4a로 만들어 iOS 파일 저장 창을 열고, 저장할 곳은 사용자가 고른다.
/// 앱 자체는 인터넷으로 아무것도 보내지 않는다.
struct RecordingSummaryView: View {
    let title: String
    let summary: PitchSummary
    /// 이미 기록에 남겼는지
    let isSaved: Bool
    /// 기록에 남기는 중인지
    let isSaving: Bool
    /// 기록에 남긴다. 메모는 비어 있을 수 있다.
    let onSave: (_ memo: String) -> Void
    /// 공유 창을 연다. true면 녹음 파일도 함께 넘긴다.
    let onShare: (_ includesAudio: Bool) -> Void
    /// 파일로 저장할 m4a를 만드는 중인지
    var isPreparingFile = false
    /// 녹음을 m4a로 만들어 파일 저장 창을 연다.
    var onSaveFile: () -> Void = {}

    @State private var didCopy = false
    @State private var isAskingMemo = false
    @State private var memo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(PitchSummary.durationLabel(summary.duration))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                stat("중앙", "\(Int(summary.median.rounded())) Hz")
                stat("범위", "\(Int(summary.p10.rounded()))–\(Int(summary.p90.rounded())) Hz")
                stat("목표 범위 안", summary.inTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
            }

            // 한 줄에 들어가면 나란히, 아주 큰 글자에서는 위아래로
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    saveButton
                    saveFileButton
                }
                VStack(spacing: 8) {
                    saveButton
                    saveFileButton
                }
            }

            HStack(spacing: 10) {
                // 녹음 파일을 같이 넘기면 오디오를 받는 앱만 공유 창에 뜬다 (ChatGPT·Claude는 안 뜸, 2026-10 아이폰 확인).
                Menu {
                    Button {
                        onShare(false)
                    } label: {
                        Label("요약 글만 보내기", systemImage: "text.alignleft")
                    }
                    Button {
                        onShare(true)
                    } label: {
                        Label("녹음 파일과 함께 보내기", systemImage: "waveform")
                    }
                } label: {
                    Label("AI에게 피드백 받기", systemImage: "square.and.arrow.up")
                }
                .menuOrder(.fixed)
                .buttonStyle(.borderedProminent)

                Button {
                    UIPasteboard.general.string = summary.feedbackRequest(title: title, includesAudio: false)
                    didCopy = true
                } label: {
                    Label(didCopy ? "복사했어요" : "요약 복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)

            Text("‘녹음 파일과 함께’는 오디오를 받는 앱만 보여요. 원하는 앱이 없으면 ‘요약 복사’ 후 붙여 넣으세요. 보낸 내용은 고른 앱으로 전송돼요. ‘파일로 저장’은 m4a 파일을 저장할 곳을 직접 골라요 (iCloud Drive를 고르면 iCloud에 올라가요).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: summary) {
            didCopy = false
        }
        .alert("기록에 남기기", isPresented: $isAskingMemo) {
            TextField("메모 (안 써도 돼요)", text: $memo)
            Button("남기기") {
                onSave(memo.trimmingCharacters(in: .whitespacesAndNewlines))
                memo = ""
            }
            Button("취소", role: .cancel) {
                memo = ""
            }
        } message: {
            Text("이 녹음의 소리와 요약을 이 기기 안에만 저장해요. 나중에 날짜별로 다시 듣고 비교할 수 있어요.")
        }
    }

    /// 기기 안 기록에 남기기 (소리 m4a + 요약 + 메모)
    private var saveButton: some View {
        Button {
            isAskingMemo = true
        } label: {
            Group {
                if isSaving {
                    Label("남기는 중…", systemImage: "hourglass")
                } else if isSaved {
                    Label("기록에 남겼어요", systemImage: "checkmark")
                } else {
                    Label("기록에 남기기", systemImage: "tray.and.arrow.down")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(UllimColor.record)  // 기록 색(초록)
        .font(.subheadline)
        .disabled(isSaved || isSaving)
    }

    /// 녹음을 m4a 파일로 저장 (저장할 곳은 iOS 파일 저장 창에서 직접 고른다)
    private var saveFileButton: some View {
        Button(action: onSaveFile) {
            Group {
                if isPreparingFile {
                    Label("만드는 중…", systemImage: "hourglass")
                } else {
                    Label("파일로 저장", systemImage: "square.and.arrow.down")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
        .disabled(isPreparingFile)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// iOS 공유 창. 글과 파일을 함께 넘긴다.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// 보내기를 마치거나 취소하면 불린다.
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
