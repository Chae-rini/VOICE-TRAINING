import SwiftUI
import UniformTypeIdentifiers

/// ‘파일로 저장’에서 iOS 파일 저장 창에 넘기는 녹음 파일 (m4a).
/// 저장할 곳(나의 iPhone, iCloud Drive 등)은 사용자가 그 창에서 직접 고른다. 앱이 저절로 내보내지는 않는다 (원칙 2).
struct AudioFileDocument: FileDocument {
    /// m4a 파일 형식. `UTType.mpeg4Audio`는 확장자가 .mp4로 붙어서 쓰지 않는다 (iOS 27 시뮬레이터에서 확인).
    static let contentType = UTType("com.apple.m4a-audio") ?? .mpeg4Audio
    static var readableContentTypes: [UTType] { [contentType] }

    let data: Data

    /// 기기 안의 m4a 파일을 읽어 담는다.
    init(url: URL) throws {
        data = try Data(contentsOf: url)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    /// 저장 창에 처음 적어 둘 파일 이름 (확장자 없이). 예: "Ullim-20261025-2012" (녹음한 날짜·시각)
    /// 로마자가 필요한 곳은 "Ullim"으로 쓴다 (CLAUDE.md). 사용자가 저장 창에서 바꿀 수 있다.
    static func defaultFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Ullim-\(formatter.string(from: date))"
    }
}
