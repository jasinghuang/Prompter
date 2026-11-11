import SwiftUI
import QuartzCore

/// Keep search presentation and focus local, rather than directly invalidating
/// the parent's model projection when these UI states change.
struct ScriptLibraryControls: View {
    @ObservedObject var library: ScriptLibraryState
    let totalCount: Int
    let visibleCount: Int
    let isPresentingContent: Bool
    let onExport: () -> Void
    @State private var searchExpanded = false
    @State private var wantsKeyboard = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if totalCount > 0 || searchExpanded { controls }
        }
        .onChange(of: isPresentingContent) { _, presenting in
            if presenting {
                wantsKeyboard = false
                searchFocused = false
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.textMuted)
                TextField("搜索标题或正文", text: $library.query)
                    .font(.body).foregroundStyle(.textPrimary).focused($searchFocused)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("script.search")
                if !library.query.isEmpty {
                    Button { library.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.textMuted).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }
            .padding(.leading, 12).padding(.trailing, library.query.isEmpty ? 12 : 0)
            .frame(minHeight: 44).background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            Button("取消") {
                searchFocused = false
                wantsKeyboard = false
                if !library.query.isEmpty { library.query = "" }
                searchExpanded = false
            }
            .font(.body).frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("library.search.cancel")
        }
        .task(id: wantsKeyboard) {
            guard wantsKeyboard else { return }
            await SearchDisplayFrame().wait()
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if searchExpanded {
                searchField
            } else {
                Menu {
                    Picker("稿件范围", selection: $library.filter) {
                        Label("全部稿件", systemImage: "doc.text").tag(ScriptFilter.all)
                        Label("星标稿件", systemImage: "star").tag(ScriptFilter.starred)
                        if !library.folders.isEmpty {
                            Section("文件夹") {
                                ForEach(library.folders, id: \.self) { name in
                                    Label(name, systemImage: "folder").tag(ScriptFilter.folder(name))
                                        .accessibilityIdentifier("filter.folder.\(name)")
                                }
                            }
                        }
                    }.pickerStyle(.inline)
                } label: {
                    HStack(spacing: 7) {
                        Text(filterTitle).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        Text("\(visibleCount)").font(.subheadline).foregroundStyle(.textMuted).monospacedDigit()
                    }
                    .foregroundStyle(.textPrimary).frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(filterTitle)
                .accessibilityValue("共 \(totalCount) 篇稿件，当前 \(visibleCount) 篇")
                .accessibilityIdentifier("library.filter")
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.textSecondary).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0 || (library.selecting && library.selected.isEmpty))
                .accessibilityLabel("导出稿件库")
                .accessibilityHint(library.selecting ? "导出选中的稿件" : "导出全部稿件或当前范围")
                .accessibilityIdentifier("library.export")
                Spacer(minLength: 0)
                Button {
                    wantsKeyboard = true
                    searchExpanded = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索稿件")
                .accessibilityIdentifier("library.search")
                Menu {
                    Picker("排序依据", selection: $library.sortKey) {
                        ForEach(SortKey.allCases, id: \.self) { key in
                            Text(key == .date ? "时间" : key.label).tag(key)
                        }
                    }.pickerStyle(.inline)
                    Picker("排列顺序", selection: $library.sortAscending) {
                        Text("升序").tag(true)
                        Text("降序").tag(false)
                    }.pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down").foregroundStyle(.textSecondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("排序方式")
                .accessibilityValue("\(library.sortKey == .date ? "时间" : library.sortKey.label)，\(library.sortAscending ? "升序" : "降序")")
                .accessibilityHint("时间按最近修改时间排序；各拍摄分类内星标稿件置顶")
                .accessibilityIdentifier("library.sort")
            }
        }.padding(.horizontal, 16).padding(.bottom, 2)
    }

    private var filterTitle: String {
        switch library.filter {
        case .all: return "全部稿件"
        case .starred: return "星标稿件"
        case .folder(let name): return name
        }
    }
}

/// Leave a display frame for the search field before keyboard preparation starts.
@MainActor
private final class SearchDisplayFrame: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private var sawFrame = false

    func wait() async {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let link = CADisplayLink(target: self, selector: #selector(tick))
                self.link = link
                link.add(to: .main, forMode: .common)
            }
        } onCancel: {
            Task { @MainActor in self.finish() }
        }
    }

    @objc private func tick() {
        // A display-link callback runs before rendering. The following tick lets
        // the previous frame render before focus can start preparing the keyboard.
        if sawFrame { finish() } else { sawFrame = true }
    }

    func finish() {
        link?.invalidate()
        link = nil
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

