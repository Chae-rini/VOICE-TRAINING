import SwiftUI

/// 대본 낭독 화면 조각. 종류·길이로 거르고, 스크롤해서 읽고, 들려줄 길이를 대본 길이에 맞출 수 있다.
struct ScriptReaderView: View {
    /// 연습 중에는 들려줄 길이를 바꾸지 못하게 한다.
    let isPracticing: Bool

    private static let anyCategory = "전체"

    private let scripts = PracticeScripts.all
    @AppStorage("scriptCategory") private var category = Self.anyCategory
    @AppStorage("scriptLength") private var length = ScriptLength.any
    @AppStorage("practiceDurationSeconds") private var practiceDuration = PracticeDuration.defaultSeconds
    @State private var index = 0
    /// [pt] 대본 상자 높이. 글자가 커지면 같이 커져서 보이는 줄 수가 크게 줄지 않는다.
    @ScaledMetric(relativeTo: .body) private var scriptHeight: CGFloat = 240

    /// 파일에 처음 나오는 순서대로의 종류 목록
    private var categories: [String] {
        var seen: Set<String> = []
        return scripts.map(\.category).filter { seen.insert($0).inserted }
    }

    private var filtered: [PracticeScript] {
        scripts.filter {
            (category == Self.anyCategory || $0.category == category) && length.contains($0.estimatedSeconds)
        }
    }

    private var current: PracticeScript? {
        filtered.indices.contains(index) ? filtered[index] : filtered.first
    }

    var body: some View {
        VStack(spacing: 8) {
            filterBar

            if let script = current {
                card(for: script)
                navigation(for: script)
            } else {
                Text(scripts.isEmpty ? "대본 파일을 읽지 못했어요." : "조건에 맞는 대본이 없어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onChange(of: category) { index = 0 }
        .onChange(of: length) { index = 0 }
    }

    private var filterBar: some View {
        HStack {
            Menu {
                Picker("종류", selection: $category) {
                    Text("전체 종류").tag(Self.anyCategory)
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                Label(category == Self.anyCategory ? "전체 종류" : category, systemImage: "line.3.horizontal.decrease.circle")
            }

            Menu {
                Picker("길이", selection: $length) {
                    ForEach(ScriptLength.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(length == .any ? "전체 길이" : length.rawValue, systemImage: "clock")
            }

            Spacer()

            Button {
                if filtered.count > 1 {
                    index = (filtered.indices.filter { $0 != index }).randomElement() ?? 0
                }
            } label: {
                Label("다른 대본", systemImage: "shuffle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(filtered.count < 2)
        }
        .font(.subheadline)
    }

    private func card(for script: PracticeScript) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(script.title)
                .font(.headline)
            Text(details(for: script))
                .font(.caption)
                .foregroundStyle(.secondary)

            // 그래프가 화면 위에 고정되어 있어서, 대본은 이 상자 안에서 넘기며 읽는다.
            ScrollView {
                WordWrappedText(text: script.text, lineSpacing: 6)
            }
            .frame(height: scriptHeight)

            if script.needsFactCheck == true {
                Text("아직 사실 확인을 거치지 않은 글이에요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        // 대본이 바뀌면 스크롤을 맨 위로 되돌린다.
        .id(script.id)
    }

    private func navigation(for script: PracticeScript) -> some View {
        let suggested = suggestedDuration(for: script)
        return VStack(spacing: 8) {
            HStack {
                Button {
                    index = max(0, index - 1)
                } label: {
                    Label("이전", systemImage: "chevron.left")
                }
                .disabled(index == 0)

                Spacer()
                Text("\(min(index, filtered.count - 1) + 1) / \(filtered.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    index = min(filtered.count - 1, index + 1)
                } label: {
                    HStack(spacing: 4) {
                        Text("다음")
                        Image(systemName: "chevron.right")
                    }
                }
                .disabled(index >= filtered.count - 1)
            }

            Button {
                practiceDuration = suggested
            } label: {
                // "30초로", "1분으로"처럼 받침에 맞는 조사를 고른다.
                Label(KoreanParticle.resolve(in: "들려줄 길이를 \(PracticeDuration.label(for: suggested))(으)로 맞추기"),
                      systemImage: "timer")
            }
            .font(.footnote)
            .disabled(isPracticing || practiceDuration == suggested)
        }
        .font(.subheadline)
    }

    private func details(for script: PracticeScript) -> String {
        let kind = [script.category, script.topic].compactMap { $0 }.joined(separator: "·")
        return "\(kind) · \(script.style) · 약 \(Int(script.estimatedSeconds.rounded()))초"
    }

    /// 대본을 끝까지 읽을 수 있게 예상 시간을 10초 단위로 올림한다.
    private func suggestedDuration(for script: PracticeScript) -> Double {
        PracticeDuration.normalized((script.estimatedSeconds / PracticeDuration.step).rounded(.up) * PracticeDuration.step)
    }
}

#Preview {
    ScriptReaderView(isPracticing: false)
        .padding()
}
