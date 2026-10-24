import SwiftUI

/// "지금 들어보기"를 누르면 들려줄 최근 길이(10초~3분)를 고르는 슬라이더.
/// 녹음은 정지할 때까지 이어지고, 이 길이만큼의 최근 소리만 남긴다.
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

            Text("‘지금 들어보기’를 누르면 최근 이만큼을 들려줘요.")
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
