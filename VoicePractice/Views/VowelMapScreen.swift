import SwiftUI

/// [모음] 탭: 실시간 모음 지도와 보는 법.
/// 녹음·듣기 조작은 [높이] 탭과 같은 아래 영역을 함께 쓴다.
struct VowelMapScreen: View {
    let audio: AudioInputManager
    /// 지도 위 숫자 아래의 안내 문구
    let caption: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VowelChartView(history: audio.history, clock: audio.graphClock, caption: caption)
                guide
            }
            .padding()
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("모음 지도 보는 법")
                .font(.subheadline.weight(.semibold))
            Text("목과 입안이 울리는 두 주파수(포먼트)로 지금 내는 모음의 위치를 보여 줘요. ‘아·에·이·오·우·으·어’ 중 하나를 2~3초 길게 내 보세요.")
            Text("• 가로(F2): 혀가 앞쪽일수록 왼쪽, 뒤쪽일수록 오른쪽")
            Text("• 세로(F1): 입을 좁게 열수록 위, 크게 열수록 아래")
            Text("같은 모음도 사람마다 위치가 달라서, 정해진 정답 위치는 없어요. 목소리가 높을수록 세로(F1)는 덜 정확하고 가로(F2)가 더 믿을 만해요. 이때는 점이 속이 빈 점선 원으로 바뀌어요.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
