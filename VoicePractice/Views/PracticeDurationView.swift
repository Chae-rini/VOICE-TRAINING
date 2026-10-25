import SwiftUI

/// "지금 들어보기"를 누르면 들려줄 최근 길이(10초~3분).
/// 자주 바꾸지 않으므로 평소에는 작은 버튼("들려줄 길이 1분")으로 접어 두고, 누르면 작은 창에서 슬라이더로 고친다.
/// 녹음은 정지할 때까지 이어지고, 이 길이만큼의 최근 소리만 남긴다.
struct PracticeDurationView: View {
    @Binding var seconds: Double
    /// 연습 중에는 바꾸지 못하게 잠근다.
    let isLocked: Bool

    @State private var isEditing = false

    private var label: String {
        PracticeDuration.label(for: seconds)
    }

    var body: some View {
        Button {
            isEditing = true
        } label: {
            Label("들려줄 길이 \(label)", systemImage: "timer")
                .monospacedDigit()
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .disabled(isLocked)
        .popover(isPresented: $isEditing) {
            editor
                .padding()
                .frame(minWidth: 300)
                .presentationCompactAdaptation(.popover)  // 아이폰에서도 화면 전체가 아닌 작은 창으로
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("들려줄 길이")
                Spacer()
                Text(label)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))

            Slider(value: snappedSeconds, in: PracticeDuration.range) {
                Text("들려줄 길이")
            } minimumValueLabel: {
                Text("10초")
            } maximumValueLabel: {
                Text("3분")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
