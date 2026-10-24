import SwiftData
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
        // 연습 기록 저장소 (기기 안). 화면에서 기록을 읽을 때 쓴다.
        .modelContainer(PracticeArchive.shared.container)
    }
}
