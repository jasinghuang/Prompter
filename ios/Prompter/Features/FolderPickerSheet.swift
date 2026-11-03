import SwiftUI

struct FolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let targets: [Script]
    let folders: [String]
    let counts: [String: Int]
    var initialFolder: String? = nil
    var errorMessage: String? = nil
    let onSelect: (String?) -> Void
    @State private var creating = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var locations: Set<String?> { targets.isEmpty ? Set([initialFolder]) : Set(targets.map(\.folder)) }
    private func selected(_ folder: String?) -> Bool { locations.count == 1 && locations.contains(folder) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "移动到文件夹") { dismiss() }
            if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.dangerRed).padding(.horizontal, 20) }
            if locations.count > 1 {
                Text("选中的稿件位于不同文件夹").font(.subheadline).foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            }
            ScrollView {
                VStack(spacing: 4) {
                    row("未分组", folder: nil)
                    ForEach(folders, id: \.self) { row($0, folder: $0) }
                    if creating {
                        VStack(spacing: 10) {
                            TextField("文件夹名称", text: $name)
                                .textFieldStyle(.plain).padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
                                .focused($nameFocused).submitLabel(.done).onSubmit(createFolder)
                                .accessibilityIdentifier("folder.name")
                            HStack {
                                Button("取消") { nameFocused = false; creating = false; name = "" }
                                    .accessibilityIdentifier("folder.cancelCreation")
                                Spacer()
                                Button("创建并移入", action: createFolder).fontWeight(.semibold)
                                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }.frame(minHeight: 44)
                        }.padding(12).modifier(LocalReveal())
                    } else {
                        Button { creating = true; nameFocused = true } label: {
                            Label("新建文件夹", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12)
                        }
                        .foregroundStyle(.accentGold).buttonStyle(.plain).accessibilityIdentifier("folder.new")
                    }
                }.padding(.horizontal, 12).padding(.bottom, 24)
            }
        }
        .background(Color.canvas)
    }

    private func row(_ label: String, folder: String?) -> some View {
        Button { onSelect(folder) } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder").foregroundStyle(.textMuted)
                Text(label).foregroundStyle(.textPrimary)
                Spacer()
                if let folder { Text("\(counts[folder, default: 0])").font(.caption).foregroundStyle(.textMuted) }
                if selected(folder) { Image(systemName: "checkmark").foregroundStyle(.accentGold) }
            }
            .padding(12).frame(minHeight: 52)
            .background(selected(folder) ? Color.accentGold.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected(folder) ? .isSelected : [])
    }
    private func createFolder() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        onSelect(cleaned)
    }
}
