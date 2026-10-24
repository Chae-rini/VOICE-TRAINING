import SwiftUI

/// 녹음 한 번의 최대 길이(10초~3분)를 고르는 슬라이더.
/// "지금 들어보기"를 누르지 않아도 이 시간이 지나면 녹음을 자동으로 들려준다.
struct PracticeDurationView: View {
    @Binding var seconds: Double
    /// 연습 중에는 바꾸지 못하게 잠근다.
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("연습 시간")
                Spacer()
                Text(PracticeDuration.label(for: seconds))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))

            Slider(value: snappedSeconds, in: PracticeDuration.range) {
                Text("연습 시간")
            } minimumValueLabel: {
                Text("10초")
            } maximumValueLabel: {
                Text("3분")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(isLocked)

            Text("녹음이 이 시간을 넘으면 자동으로 들려줘요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // 슬라이더를 움직이면 10초 단위로 맞춘다.
    private var snappedSeconds: Binding<Double> {
        Binding(
            get: { seconds },
            set: { seconds = PracticeDuration.normalized($0) }
        )
    }
}

#Preview {
    @Previewable @State var seconds = PracticeDuration.defaultSeconds
    PracticeDurationView(seconds: $seconds, isLocked: false)
        .padding()
}
