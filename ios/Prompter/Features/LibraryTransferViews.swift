import SwiftUI
import SwiftData

struct LibraryExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let request: LibraryExportRequest
    @State private var currentOnly: Bool
    @State private var prepared: PreparedLibraryExport?
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var saved = false
    @State private var retry = 0

    init(request: LibraryExportRequest) {
        self.request = request
        _currentOnly = State(initialValue: request.prefersCurrent && !request.onlySelected)
    }
    private var records: [LibraryArchive.Record] {
        currentOnly ? request.records.filter { request.currentIDs.contains($0.id) } : request.records
    }
    private struct Preparation: Hashable { let current: Bool; let retry: Int }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: request.onlySelected ? "导出已选稿件" : "导出稿件库") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !request.onlySelected && request.currentIDs.count != request.records.count {
                        Picker("导出范围", selection: $currentOnly) {
                            Text("全部稿件").tag(false)
                            Text(request.currentTitle).tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("archive.exportScope")
                    }
                    VStack(spacing: 0) {
                        TransferStatRow(title: "稿件", value: "\(records.count) 篇")
                        TransferStatRow(title: "文件夹", value: "\(Set(records.compactMap(\.folder)).count) 个")
                        TransferStatRow(title: "星标", value: "\(records.filter(\.starred).count) 篇")
                        TransferStatRow(title: "已拍摄", value: "\(records.filter(\.isFilmed).count) 篇")
                    }
                    Label("标题、正文、文件夹归属、星标、拍摄状态及创建／修改时间会一起保留。", systemImage: "doc.text")
                        .font(.subheadline).foregroundStyle(.textSecondary)
                    if let prepared {
                        Text(prepared.name + ".prompter").font(.subheadline).textSelection(.enabled)
                            .accessibilityIdentifier("archive.exportName")
                    } else if errorMessage == nil {
                        ProgressView("正在生成稿件库…").frame(maxWidth: .infinity)
                    }
                    if saved { Label("文件已保存", systemImage: "checkmark.circle").foregroundStyle(.successGreen) }
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.dangerRed)
                        Button("重试") { retry += 1 }.frame(minHeight: 44)
                    }
                }.padding(20)
            }
            if let prepared {
                Group {
                    if verticalSizeClass == .compact {
                        HStack(spacing: 12) { shareButton(prepared); saveButton }
                    } else {
                        VStack(spacing: 8) { shareButton(prepared); saveButton }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .background(Color.canvas)
        .task(id: Preparation(current: currentOnly, retry: retry)) {
            prepared = nil; errorMessage = nil; saved = false
            let archive = LibraryArchive(scripts: records)
            do {
                let result = try await Task.detached(priority: .userInitiated) { try LibraryExportFiles.prepare(archive) }.value
                guard !Task.isCancelled else { return }
                prepared = result
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $saving,
                      document: prepared.map { LibraryArchiveDocument(data: $0.data) },
                      contentType: .prompterLibrary, defaultFilename: prepared?.name ?? "稿件库") { result in
            switch result {
            case .success: saved = true
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
            }
        }
    }

    private func shareButton(_ prepared: PreparedLibraryExport) -> some View {
        ShareLink(item: prepared.file, preview: SharePreview("稿件库 · \(records.count) 篇", image: Image("Logo"))) {
            Text("分享文件").frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.canvas).background(Color.accentGold, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("archive.share")
    }
    private var saveButton: some View {
        Button { saving = true } label: {
            Label("存储到“文件”", systemImage: "folder").frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(PressableStyle()).accessibilityIdentifier("archive.saveFile")
    }
}

struct LibraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let incoming: LibraryTransferCoordinator.Incoming
    let onImported: () -> Void
    @State private var plan: LibraryArchiveService.ImportPlan?
    @State private var policy = LibraryArchiveService.ConflictPolicy.keepLocal
    @State private var report: LibraryArchiveService.ImportReport?
    @State private var errorMessage: String?
    @State private var allConflicts = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: report == nil ? "导入稿件库" : "导入结果") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(incoming.name, systemImage: "doc.text").font(.headline).lineLimit(2)
                    Text("\(incoming.archive.scripts.count) 篇稿件 · \(incoming.archive.folders.count) 个文件夹")
                        .font(.subheadline).foregroundStyle(.textSecondary)
                    if let report {
                        Label("导入完成", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold))
                            .foregroundStyle(.successGreen).accessibilityIdentifier("archive.importSuccess")
                        VStack(spacing: 0) {
                            TransferStatRow(title: "新增", value: "\(report.added) 篇", identifier: "archive.result.added")
                            TransferStatRow(title: "更新", value: "\(report.updated) 篇", identifier: "archive.result.updated")
                            TransferStatRow(title: "保留本机", value: "\(report.kept) 篇")
                            TransferStatRow(title: "相同，已跳过", value: "\(report.skipped) 篇")
                        }
                    } else if let plan {
                        VStack(spacing: 0) {
                            TransferStatRow(title: "新增稿件", value: "\(plan.newRecords.count) 篇", identifier: "archive.plan.new")
                            TransferStatRow(title: "完全相同，跳过", value: "\(plan.identicalCount) 篇", identifier: "archive.plan.same")
                            TransferStatRow(title: "与本机有差异", value: "\(plan.conflicts.count) 篇", identifier: "archive.plan.conflicts")
                        }
                        if !plan.conflicts.isEmpty {
                            Text("差异稿件如何处理").font(.headline)
                            Picker("差异稿件", selection: $policy) {
                                Text("保留本机版本").tag(LibraryArchiveService.ConflictPolicy.keepLocal)
                                Text("使用文件版本").tag(LibraryArchiveService.ConflictPolicy.useFile)
                            }.pickerStyle(.segmented).accessibilityIdentifier("archive.conflictPolicy")
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(allConflicts ? plan.conflicts : Array(plan.conflicts.prefix(3))) { conflict in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(conflict.incoming.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text("差异：\(changedFields(conflict))")
                                        Text(conflict.local.deletedAt != nil ? "本机：已删除" : "本机：\(status(filmed: conflict.local.isFilmed, starred: conflict.local.starred))")
                                        Text("文件：\(status(filmed: conflict.incoming.isFilmed, starred: conflict.incoming.starred))")
                                        if conflict.local.folder != conflict.incoming.folder {
                                            Text("文件夹：\(conflict.local.folder ?? "未分组") → \(conflict.incoming.folder ?? "未分组")")
                                        }
                                    }.font(.subheadline).foregroundStyle(.textSecondary)
                                }
                            }
                            if plan.conflicts.count > 3 {
                                Button(allConflicts ? "收起差异稿件" : "查看全部 \(plan.conflicts.count) 篇差异稿件") { allConflicts.toggle() }
                                    .frame(minHeight: 44)
                            }
                        } else if plan.newRecords.isEmpty {
                            Text(incoming.archive.scripts.isEmpty ? "文件中没有稿件。" : "文件中的稿件与本机完全相同，无需重复导入。")
                                .font(.body).foregroundStyle(.textSecondary)
                        }
                    } else if errorMessage == nil { ProgressView("正在核对本机稿件…") }
                    if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.dangerRed).accessibilityIdentifier("archive.importError") }
                }.padding(20)
            }
            if let plan {
                let actionable = !plan.newRecords.isEmpty || !plan.conflicts.isEmpty
                Button(report != nil || !actionable ? "完成" : importTitle(plan)) {
                    if report != nil || !actionable { dismiss() } else { performImport(plan) }
                }
                .font(.body.weight(.semibold)).foregroundStyle(Color.canvas)
                .frame(maxWidth: .infinity, minHeight: 48).background(Color.accentGold, in: Capsule())
                .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 12)
                .accessibilityIdentifier(report != nil || !actionable ? "archive.done" : "archive.confirmImport")
            }
        }
        .background(Color.canvas)
        .task { reloadPlan() }
    }

    private func status(filmed: Bool, starred: Bool) -> String {
        (filmed ? "已拍摄" : "未拍摄") + " · " + (starred ? "已星标" : "未星标")
    }
    private func changedFields(_ conflict: LibraryArchiveService.Conflict) -> String {
        if conflict.local.deletedAt != nil { return "本机已删除" }
        var fields: [String] = []
        if conflict.local.title != conflict.incoming.title { fields.append("标题") }
        if conflict.local.content != conflict.incoming.content { fields.append("正文") }
        if conflict.local.folder != conflict.incoming.folder { fields.append("文件夹") }
        if conflict.local.starred != conflict.incoming.starred { fields.append("星标") }
        if conflict.local.isFilmed != conflict.incoming.isFilmed { fields.append("拍摄状态") }
        return fields.isEmpty ? "创建／修改时间" : fields.joined(separator: "、")
    }
    private func importTitle(_ plan: LibraryArchiveService.ImportPlan) -> String {
        if policy == .useFile && !plan.conflicts.isEmpty {
            return plan.newRecords.isEmpty ? "更新 \(plan.conflicts.count) 篇稿件" : "导入 \(plan.newRecords.count) 篇并更新 \(plan.conflicts.count) 篇"
        }
        return plan.newRecords.isEmpty ? "保留本机版本并完成" : "导入 \(plan.newRecords.count) 篇新稿件"
    }
    private func reloadPlan() {
        do { plan = try LibraryArchiveService.plan(incoming.archive, in: context) }
        catch { errorMessage = error.localizedDescription }
    }
    private func performImport(_ plan: LibraryArchiveService.ImportPlan) {
        do {
            report = try LibraryArchiveService.apply(plan, policy: policy, in: context)
            errorMessage = nil; onImported()
        } catch {
            errorMessage = error.localizedDescription
            reloadPlan()
        }
    }
}

private struct TransferStatRow: View {
    let title: String
    let value: String
    var identifier: String = ""
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.textSecondary).monospacedDigit() }
            .font(.body).frame(minHeight: 46)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }
}
