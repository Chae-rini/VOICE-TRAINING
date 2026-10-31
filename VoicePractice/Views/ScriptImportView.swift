import SwiftUI

/// AI 대본 가져오기 화면 (2026-10-31~): ① 부탁 글을 만들어 AI 앱으로 보내고 ② AI가 쓴 답을 붙여넣어 ‘내 대본’에 남긴다.
/// 울림은 인터넷에 연결하지 않는다 (원칙 2). 부탁 글은 사용자가 공유 창에서 고른 앱으로만 나간다.
struct ScriptImportView: View {
    /// 저장한 뒤 (대본 화면이 ‘내 대본’ 종류를 보여 주게)
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var request = ScriptImport.Request()
    @State private var didCopy = false
    @State private var pasted = ""
    @State private var drafts: [ScriptImport.Draft] = []
    @State private var saveFailed = false

    private var prompt: String {
        ScriptImport.prompt(request)
    }

    var body: some View {
        NavigationStack {
            Form {
                requestSection
                pasteSection
                if !drafts.isEmpty {
                    previewSection
                }
            }
            .navigationTitle("AI 대본 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        // 고른 조건이 바뀌면 부탁 글도 바뀌므로 ‘복사했어요’를 지운다
        .onChange(of: request) { didCopy = false }
    }

    private var requestSection: some View {
        Section {
            Stepper("\(request.count)편", value: $request.count, in: ScriptImport.countRange)
            Picker("한 편 길이", selection: $request.seconds) {
                ForEach(ScriptImport.secondsOptions, id: \.self) { Text("약 \($0)초").tag($0) }
            }
            Picker("말투", selection: $request.style) {
                Text("섞어서").tag(String?.none)
                ForEach(ScriptImport.styleOptions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            TextField("주제 (비워 두면 일상 장면)", text: $request.topic)
            ShareLink(item: prompt) {
                Label("AI에게 대본 부탁하기", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = prompt
                didCopy = true
            } label: {
                Label(didCopy ? "복사했어요" : "부탁 글 복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("1. AI에게 부탁하기")
        } footer: {
            Text("부탁 글을 쓰시는 AI 앱에 보내거나 붙여 넣으세요. 울림은 인터넷에 연결하지 않아요. 보낸 내용은 고른 앱으로 전송돼요.")
        }
    }

    private var pasteSection: some View {
        Section {
            PasteButton(payloadType: String.self) { strings in
                // 붙여넣기는 시스템이 주는 단추라 허락을 따로 묻지 않는다
                pasted = strings.joined(separator: "\n")
            }
            TextEditor(text: $pasted)
                .frame(minHeight: 120)
                .accessibilityLabel("AI가 쓴 대본")
        } header: {
            Text("2. AI가 쓴 대본 붙여넣기")
        } footer: {
            Text("AI의 답을 복사한 뒤 ‘붙여넣기’를 누르거나 위 칸에 붙여 넣으세요. ‘제목:’ 줄은 제목으로 쓰고, ‘---’ 줄로 나눈 글은 여러 편으로 가져와요.")
        }
        // 붙여넣은 글이 바뀌면 미리 보기를 새로 만든다 (고친 제목도 처음으로 돌아간다)
        .onChange(of: pasted) { drafts = ScriptImport.parse(pasted) }
    }

    private var previewSection: some View {
        Group {
            Section {
                ForEach(drafts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("제목", text: $drafts[index].title)
                            .font(.headline)
                        Text(drafts[index].text)
                            .font(.footnote)
                            .lineLimit(4)
                        Text("약 \(Int(PracticeScript.estimatedSeconds(of: drafts[index].text).rounded()))초")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            } header: {
                Text("미리 보기 · \(drafts.count)편")
            } footer: {
                Text("제목을 눌러 고칠 수 있어요. 가져오지 않을 대본은 왼쪽으로 밀어 빼세요.")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("\(drafts.count)편을 내 대본에 남기기")
                        .frame(maxWidth: .infinity)
                }
                .disabled(drafts.contains { $0.title.trimmingCharacters(in: .whitespaces).isEmpty })
                if saveFailed {
                    Label("대본을 남기지 못했어요. 저장 공간을 확인해 주세요.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("[높이] 대본의 ‘내 대본’ 종류에 남아요. 이 기기 안에만 있어요.")
            }
        }
    }

    private func save() {
        do {
            try PracticeArchive.shared.saveImportedScripts(drafts)
        } catch {
            saveFailed = true
            return
        }
        onSaved()
        dismiss()
    }
}

#Preview {
    ScriptImportView(onSaved: {})
}
