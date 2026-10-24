import SwiftUI

/// 마이크 권한이 거부됐을 때 이유와 다시 켜는 방법을 안내한다.
struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("마이크 권한이 꺼져 있어요")
                    .font(.title2.bold())
                Text("목소리의 높이를 분석하려면 마이크가 필요해요.\n녹음은 직접 공유할 때만 기기 밖으로 나가요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("마이크를 켜는 방법")
                    .font(.headline)
                Text("1. 아래 ‘설정 열기’를 눌러요.")
                Text("2. ‘마이크’ 스위치를 켜요.")
                Text("3. 이 앱으로 돌아와요. 앱이 다시 시작될 수 있어요.")
                Text("또는 설정 앱 → 개인정보 보호 및 보안 → 마이크에서 켤 수도 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    PermissionDeniedView()
}
