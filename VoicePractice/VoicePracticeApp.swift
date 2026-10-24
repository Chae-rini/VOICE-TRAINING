import SwiftUI

@main
struct VoicePracticeApp: App {
    init() {
        // 예전 버전부터 쓰던 사람의 목표 범위를 그대로 남긴다 (처음 한 번만 확인).
        TargetRangeStore.preserveExistingTarget(in: .standard)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
