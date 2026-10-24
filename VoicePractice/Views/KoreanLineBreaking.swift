import SwiftUI
import UIKit

/// 한글을 띄어쓰기 단위로 줄바꿈하는 글 상자.
/// SwiftUI의 Text는 한글을 글자 단위로 줄바꿈해서 "때문 / 에"처럼 단어가 끊긴다.
/// 소리 내어 읽을 때는 단어가 끊기면 흐름이 깨지므로, UIKit의 UILabel에
/// 한글 단어 우선 줄바꿈(hangulWordPriority)을 켜서 SwiftUI 화면 안에 넣는다.
struct WordWrappedText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var weight: UIFont.Weight = .regular
    var alignment: NSTextAlignment = .natural
    var lineSpacing: CGFloat = 0

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakStrategy = .hangulWordPriority
        // 가로 길이는 SwiftUI가 정해 준 폭을 따르게 한다.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        // 글자 크기 설정(다이내믹 타입)을 따르면서 굵기만 바꾼다.
        let baseSize = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        let font = UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: .systemFont(ofSize: baseSize, weight: weight))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        paragraph.lineBreakStrategy = .hangulWordPriority

        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.label,
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height.rounded(.up))
    }
}
