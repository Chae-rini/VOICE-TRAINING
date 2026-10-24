/// 한국어 단모음 7개.
/// 현대 서울말에서는 ㅐ와 ㅔ가 거의 같은 소리라서 하나(에)로 묶는다.
enum KoreanVowel: String, CaseIterable {
    case a = "아"
    case eo = "어"
    case o = "오"
    case u = "우"
    case eu = "으"
    case i = "이"
    case e = "에"

    /// 한글 음절 하나의 가운데 소리(중성)가 단모음이면 그 모음, 아니면 nil.
    /// 이중모음(ㅑ·ㅘ·ㅢ 등)과 한글이 아닌 글자도 nil.
    init?(syllable: Unicode.Scalar) {
        // 한글 음절의 코드 = 0xAC00 + (초성 × 21 + 중성) × 28 + 종성
        let firstSyllable: UInt32 = 0xAC00  // 가
        let lastSyllable: UInt32 = 0xD7A3   // 힣
        guard (firstSyllable...lastSyllable).contains(syllable.value) else { return nil }

        let medial = (syllable.value - firstSyllable) % (21 * 28) / 28
        switch medial {
        case 0: self = .a      // ㅏ
        case 4: self = .eo     // ㅓ
        case 8: self = .o      // ㅗ
        case 13: self = .u     // ㅜ
        case 18: self = .eu    // ㅡ
        case 20: self = .i     // ㅣ
        case 1, 5: self = .e   // ㅐ, ㅔ
        default: return nil
        }
    }

    /// 문장에 각 단모음이 몇 번 나오는지 센다.
    /// 글자(표기) 기준이라 "같이[가치]"처럼 발음이 바뀌는 경우는 반영하지 않는다.
    static func counts(in text: String) -> [KoreanVowel: Int] {
        var counts: [KoreanVowel: Int] = [:]
        for scalar in text.unicodeScalars {
            if let vowel = KoreanVowel(syllable: scalar) {
                counts[vowel, default: 0] += 1
            }
        }
        return counts
    }

    /// 많이 나온 모음부터 최대 `limit`개. 개수가 같으면 아·어·오·우·으·이·에 순서.
    static func mostFrequent(in text: String, limit: Int = 2) -> [(vowel: KoreanVowel, count: Int)] {
        let counts = counts(in: text)
        let present = allCases
            .map { (vowel: $0, count: counts[$0, default: 0]) }
            .filter { $0.count > 0 }
        return present.enumerated()
            .sorted { lhs, rhs in
                lhs.element.count != rhs.element.count
                    ? lhs.element.count > rhs.element.count
                    : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }
}
