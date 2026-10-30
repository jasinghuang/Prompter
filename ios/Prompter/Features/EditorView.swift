import SwiftUI
import SwiftData

/// 编辑页（M1 精简版：标题 + 正文 + 保存；分组/智能拆分在 M2 补齐）
struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let script: Script? // nil = 新建
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    saveAndClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Color.surface.opacity(0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                TextField("稿件标题", text: $title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            TextEditor(text: $content)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .background(Color.canvas)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = script?.title ?? ""
            content = script?.content ?? ""
        }
    }

    private func saveAndClose() {
        if let script {
            script.title = title.isEmpty ? "未命名稿件" : title
            script.content = content
            script.updatedAt = Date()
        } else {
            let newScript = Script(title: title.isEmpty ? "未命名稿件" : title, content: content)
            context.insert(newScript)
        }
        dismiss()
    }
}
