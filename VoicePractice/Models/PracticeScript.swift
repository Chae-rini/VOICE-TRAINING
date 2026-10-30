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

/// [높이] 대본 화면의 섞인 순서 (2026-10-31~, 그 전에는 늘 1번 대본부터 파일 순서대로였다).
/// 열 때마다 다른 대본부터 보이고, 이전·다음은 이 순서대로 넘어간다.
/// 같은 씨앗(seed)이면 같은 순서라, 화면이 다시 그려져도 순서가 바뀌지 않는다. 거르기를 바꾸면 씨앗을 바꿔 다시 섞는다.
enum ScriptOrder {
    /// 0..<count를 섞은 자리 목록
    static func shuffled(count: Int, seed: UInt64) -> [Int] {
        var generator = SplitMix64(seed: seed)
        return Array(0..<count).shuffled(using: &generator)
    }
}

/// 씨앗을 고정할 수 있는 난수 생성기 (SplitMix64). 같은 씨앗이면 같은 수열이 나온다.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
