import Testing
import UIKit
@testable import VoicePractice

/// 울림 색이 글자로 써도 읽히는지 대비(WCAG)를 잰다. 기준: 보통 글자 4.5:1, 굵고 큰 글자·선 3:1.
@MainActor
struct UllimThemeTests {
    private func resolved(_ name: String, _ style: UIUserInterfaceStyle) throws -> UIColor {
        let color = try #require(UIColor(named: name), "\(name) 색이 Assets에 없음")
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// 상대 휘도 (WCAG 2.x)
    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test("밝은 모드: 역할 색 글자가 흰 바탕과 카드 바탕(secondarySystemBackground)에서 4.5:1 이상",
          arguments: ["UllimPink", "UllimPurple", "UllimGreen", "AccentColor"])
    func lightText(name: String) throws {
        let color = try resolved(name, .light)
        let card = UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(contrast(color, .white) >= 4.5)
        #expect(contrast(color, card) >= 4.5)
    }

    @Test("어두운 모드: 분홍·보라·초록 글자가 검은 바탕과 카드 바탕에서 4.5:1 이상",
          arguments: ["UllimPink", "UllimPurple", "UllimGreen"])
    func darkText(name: String) throws {
        let color = try resolved(name, .dark)
        let card = UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(contrast(color, .black) >= 4.5)
        #expect(contrast(color, card) >= 4.5)
    }

    @Test("흰 글자가 얹히는 채운 버튼(파랑 강조색, 보라 채움)은 두 모드 모두 흰 글자 4.5:1 이상",
          arguments: ["AccentColor", "UllimPurpleFill"])
    func filledButtons(name: String) throws {
        #expect(contrast(try resolved(name, .light), .white) >= 4.5)
        #expect(contrast(try resolved(name, .dark), .white) >= 4.5)
    }

    @Test("강조색(파랑) 버튼 위의 흰 글자는 두 모드 모두 4.5:1 이상, 어두운 바탕 위 파랑 글자는 3:1 이상")
    func accent() throws {
        let light = try resolved("AccentColor", .light)
        let dark = try resolved("AccentColor", .dark)
        let darkCard = UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(contrast(light, .white) >= 4.5)
        #expect(contrast(dark, .white) >= 4.5)
        #expect(contrast(dark, .black) >= 4.5)
        #expect(contrast(dark, darkCard) >= 3)
    }

    @Test("어두운 모드 색은 아이콘 색 그대로 (분홍 #F85897, 보라 #C199EF, 초록 #61DAAF)", arguments: [
        ("UllimPink", 0xF8, 0x58, 0x97), ("UllimPurple", 0xC1, 0x99, 0xEF), ("UllimGreen", 0x61, 0xDA, 0xAF),
    ])
    func darkMatchesIcon(name: String, red: Int, green: Int, blue: Int) throws {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        try resolved(name, .dark).getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(Int((r * 255).rounded()) == red)
        #expect(Int((g * 255).rounded()) == green)
        #expect(Int((b * 255).rounded()) == blue)
    }
}
