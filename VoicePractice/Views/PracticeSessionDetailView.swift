import SwiftUI
import UIKit

/// 연습 기록 하나: 연습 전체와 녹음마다의 숫자, AI에게 보낼 요약 글.
/// 연습 중에는 다음 녹음이 시작되면 요약 카드가 사라지므로, 녹음마다의 숫자를 여기서 다시 보고 보낸다.
/// 소리는 남지 않으므로 글만 보낸다. 보낼 앱은 사용자가 iOS 공유 창에서 고른다 (원칙 2).
struct PracticeSessionDetailView: View {
    let session: PracticeSession

    @State private var didCopy = false

    var body: some View {
        let summary = session.summary
        let request = summary.feedbackRequest()

        Form {
            Section {
                LabeledContent("연습한 때", value: summary.startedAt.formatted(.dateTime.year().month().day().weekday().hour().minute()))
                LabeledContent("연습 시간", value: PracticeHistory.totalLabel(session.practiceSeconds))
                LabeledContent("녹음", value: "\(summary.takeCount)번")
                LabeledContent("말한 언어", value: summary.language.label)
            }

            Section("연습 전체 높이") {
                LabeledContent("중앙", value: "\(Int(summary.pitch.median.rounded())) Hz")
                LabeledContent("범위 (아래 10%~위 10%)",
                               value: "\(Int(summary.pitch.p10.rounded()))–\(Int(summary.pitch.p90.rounded())) Hz")
                LabeledContent("목소리가 잡힌 시간", value: PitchSummary.durationLabel(summary.pitch.voicedSeconds))
                if let target = summary.pitch.target {
                    LabeledContent("정지한 때 목표 범위", value: "\(Int(target.lowerBound))–\(Int(target.upperBound)) Hz")
                    LabeledContent("목표 범위 안",
                                   value: summary.pitch.inTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                } else {
                    LabeledContent("정지한 때 목표 범위", value: "정하지 않음")
                }
            }

            Section {
                if summary.takes.isEmpty {
                    Text("이 연습에는 녹음마다 기록이 없어요. 녹음마다 기록은 이 기능이 생긴 뒤의 연습부터 남아요.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.takes, id: \.round) { take in
                        takeRow(take, sessionTarget: summary.pitch.target)
                    }
                }
            } header: {
                Text("녹음마다")
            } footer: {
                Text("‘지금 들어보기’를 누르거나 녹음 중에 정지할 때마다 하나씩 남아요. 목소리가 잡히지 않은 녹음은 빠져요. 목표 범위 안 비율은 그 녹음을 마친 때의 목표 범위로 쟀어요.")
            }

            Section {
                ShareLink(item: request) {
                    Label("AI에게 피드백 받기", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = request
                    didCopy = true
                } label: {
                    Label(didCopy ? "복사했어요" : "요약 복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
            } footer: {
                Text("연습 전체와 녹음마다의 숫자를 요약 글로 보내요. 소리는 남지 않아 함께 보낼 수 없어요. 보낸 내용은 고른 앱으로 전송돼요.")
            }
        }
        .navigationTitle(session.startedAt.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func takeRow(_ take: PracticeSessionLog.Take, sessionTarget: ClosedRange<Double>?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(take.round)번째 녹음")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(PitchSummary.durationLabel(take.pitch.duration))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(take.numbersLine)
                .font(.footnote)
                .monospacedDigit()
            if let target = take.pitch.target, target != sessionTarget {
                Text("그때 목표 \(Int(target.lowerBound))–\(Int(target.upperBound)) Hz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
