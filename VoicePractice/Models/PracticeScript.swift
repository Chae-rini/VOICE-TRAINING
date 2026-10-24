import Foundation

/// 낭독 연습 대본 한 편. 본문은 PracticeScripts.json에 들어 있고, 그 파일을 직접 고쳐도 된다.
struct PracticeScript: Codable, Identifiable, Equatable {
    let id: String
    let category: String       // 대화문, 독백, 수필, 감성 내레이션, 소설, 산문시, 비문학, 음색 교정
    let topic: String?         // 비문학의 분야: 과학, 인문, 사회, 예술, 생활
    let style: String          // 해요체, 합쇼체, 반말, 문어체
    let title: String
    let text: String
    let focusVowel: String?    // 음색 교정 대본이 집중하는 모음
    let needsFactCheck: Bool?  // 아직 사람이 사실 관계를 확인하지 않은 비문학 글

    /// 소리 내어 읽는 속도 가정 [음절/s]. 실제 낭독 시간과 비교해 나중에 보정할 수 있다.
    static let syllablesPerSecond = 4.5

    /// 한글 음절 수 (공백·문장부호 제외)
    var syllableCount: Int {
        text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
    }

    /// 예상 낭독 시간 [s]
    var estimatedSeconds: Double {
        Double(syllableCount) / Self.syllablesPerSecond
    }
}

enum PracticeScripts {
    /// 앱에 들어 있는 대본 전체. 파일이 없거나 형식이 틀리면 빈 배열이다 (테스트가 잡아낸다).
    static let all: [PracticeScript] = load(from: .main)

    static func load(from bundle: Bundle) -> [PracticeScript] {
        guard let url = bundle.url(forResource: "PracticeScripts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let scripts = try? JSONDecoder().decode([PracticeScript].self, from: data) else {
            return []
        }
        return scripts
    }
}

/// 대본을 예상 길이로 거르는 기준.
enum ScriptLength: String, CaseIterable, Identifiable {
    case any = "전체 길이"
    case short = "짧게 (20초까지)"
    case medium = "보통 (20~40초)"
    case long = "길게 (40초 넘게)"

    var id: Self { self }

    func contains(_ seconds: Double) -> Bool {
        switch self {
        case .any: true
        case .short: seconds <= 20
        case .medium: seconds > 20 && seconds <= 40
        case .long: seconds > 40
        }
    }
}
