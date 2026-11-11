import Foundation
import CryptoKit

struct SpeechModelAsset {
    let name: String
    let bytes: Int64
    let sha256: String
}

enum ParaformerModel {
    static let revision = "8e40c43232a1c5c66c82111efc5820d3accca11b"
    static let repository = "csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en"
    // Same three SHA-256 hashes, verified against the ModelScope repository API.
    // Keep literal bases here so the Mac build script shares this source order.
    static let downloadBases = [
        "https://modelscope.cn/models/pengzhendong/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/c9d662eca7ca87765078148501659faa24e842ed",
        "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/8e40c43232a1c5c66c82111efc5820d3accca11b"
    ]
    static let assets: [SpeechModelAsset] = [
        .init(name: "encoder.int8.onnx", bytes: 165_462_184,
              sha256: "81a70226a8934e6ed92aa1d4fc486b428b5398e2f2619ed4897b7294cab90e9a"),
        .init(name: "decoder.int8.onnx", bytes: 71_664_561,
              sha256: "f3cca9f77bb9d93c8fcbfb63ae617b6b1ee96818df3aa3b151c40658fe38594f"),
        .init(name: "tokens.txt", bytes: 75_756,
              sha256: "59aba8873a2ed1e122c25fee421e25f283b63290efbde85c1f01a853d83cb6e6")
    ]
    static let totalBytes = assets.reduce(Int64(0)) { $0 + $1.bytes }

    static func url(for asset: SpeechModelAsset) -> URL {
        urls(for: asset)[0]
    }

    static func urls(for asset: SpeechModelAsset) -> [URL] {
        downloadBases.map { URL(string: "\($0)/\(asset.name)")! }
    }

    /// Bundled assets are verified when preparing the signed app. Downloaded
    /// assets are verified before installation; partial directories never qualify.
    static func isInstalled(at directory: URL) -> Bool {
        (try? String(contentsOf: directory.appendingPathComponent("verified"), encoding: .utf8)) == revision
            && assets.allSatisfy {
                let size = try? directory.appendingPathComponent($0.name).resourceValues(forKeys: [.fileSizeKey]).fileSize
                return Int64(size ?? 0) == $0.bytes
            }
    }

    static func verify(_ url: URL, asset: SpeechModelAsset) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? 0) == asset.bytes else { throw SpeechModelError.invalidFile(asset.name) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let checksum = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard checksum == asset.sha256 else { throw SpeechModelError.invalidFile(asset.name) }
    }
}

enum SpeechModelError: LocalizedError {
    case invalidFile(String), http(Int), missing
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "模型文件校验失败，请重新下载。"
        case .http(let code): return "模型下载失败（HTTP \(code)），请检查网络后重试。"
        case .missing: return "请先在设置中下载离线语音模型。"
        }
    }
}

enum SpeechModelDownloadPhase {
    case connecting, downloading, verifying, installing
    var label: String {
        switch self {
        case .connecting: return "正在连接下载服务器…"
        case .downloading: return "正在下载离线模型"
        case .verifying: return "正在校验模型文件…"
        case .installing: return "正在安装离线模型…"
        }
    }
}

@MainActor
final class SpeechModelStore: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var progress: Double?
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var downloadPhase: SpeechModelDownloadPhase = .connecting
    @Published private(set) var message: String?
    let directory: URL
    let isBundled: Bool
    private var download: Task<Void, Never>?
    private var installID: UUID?
    private var transferID: UUID?

    init(root: URL? = nil, bundledDirectory: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // An explicit root isolates download tests from the app's bundled assets.
        let bundled = bundledDirectory ?? (root == nil ? Bundle.main.url(forResource: "ParaformerModel", withExtension: nil) : nil)
        if let bundled, ParaformerModel.isInstalled(at: bundled) {
            directory = bundled
            isBundled = true
        } else {
            directory = base.appendingPathComponent("SpeechModels/paraformer-\(ParaformerModel.revision)", isDirectory: true)
            isBundled = false
        }
        refresh()
    }

    func refresh() {
        ready = ParaformerModel.isInstalled(at: directory)
    }

    func cancel() {
        guard download != nil else { return }
        installID = nil
        transferID = nil
        download?.cancel()
        download = nil
        progress = nil
        message = "已取消下载，可稍后重试。"
    }

    func downloadModel() {
        guard download == nil, !ready else { return }
        let id = UUID()
        installID = id
        progress = 0
        downloadedBytes = 0
        downloadPhase = .connecting
        message = nil
        download = Task { [weak self] in
            guard let self else { return }
            let staging = directory.deletingLastPathComponent().appendingPathComponent("install-\(id)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var parent = directory.deletingLastPathComponent()
                try parent.setResourceValues(values)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 20
                configuration.timeoutIntervalForResource = 1800
                var completed: Int64 = 0
                for asset in ParaformerModel.assets {
                    try Task.checkCancellation()
                    let previous = completed
                    var lastError: Error = SpeechModelError.missing
                    var verified = false
                    for source in ParaformerModel.urls(for: asset) {
                        try Task.checkCancellation()
                        let target = staging.appendingPathComponent(asset.name)
                        do {
                            let transfer = UUID()
                            transferID = transfer
                            downloadPhase = .connecting
                            downloadedBytes = previous
                            progress = min(0.99, Double(previous) / Double(ParaformerModel.totalBytes))
                            let downloader = SpeechModelDownloader(configuration: configuration) { [weak self] received in
                                Task { @MainActor in
                                    guard let self, self.installID == id, self.transferID == transfer else { return }
                                    self.downloadedBytes = max(self.downloadedBytes, previous + min(asset.bytes, received))
                                    self.progress = min(0.99, Double(self.downloadedBytes) / Double(ParaformerModel.totalBytes))
                                    self.downloadPhase = .downloading
                                }
                            }
                            let (temporary, response) = try await downloader.download(from: source)
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            try Task.checkCancellation()
                            transferID = nil
                            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                                throw SpeechModelError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
                            }
                            downloadedBytes = previous + asset.bytes
                            progress = min(0.99, Double(downloadedBytes) / Double(ParaformerModel.totalBytes))
                            downloadPhase = .verifying
                            try FileManager.default.moveItem(at: temporary, to: target)
                            let verification = Task.detached(priority: .utility) { try ParaformerModel.verify(target, asset: asset) }
                            try await withTaskCancellationHandler {
                                try await verification.value
                            } onCancel: { verification.cancel() }
                            verified = true
                            break
                        } catch {
                            transferID = nil
                            try? FileManager.default.removeItem(at: target)
                            try Task.checkCancellation()
                            let native = error as NSError
                            if error is CancellationError || (native.domain == NSURLErrorDomain && native.code == NSURLErrorCancelled) {
                                throw error
                            }
                            lastError = error
                        }
                    }
                    guard verified else { throw lastError }
                    completed += asset.bytes
                }
                try Task.checkCancellation()
                guard installID == id else { return }
                downloadPhase = .installing
                try ParaformerModel.revision.write(to: staging.appendingPathComponent("verified"), atomically: true, encoding: .utf8)
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                try FileManager.default.moveItem(at: staging, to: directory)
                refresh()
                message = nil
            } catch {
                guard installID == id else { return }
                message = Self.downloadErrorMessage(error)
            }
            guard installID == id else { return }
            installID = nil
            transferID = nil
            progress = nil
            download = nil
        }
    }

    static func downloadErrorMessage(_ error: Error) -> String {
        let networkError = error as NSError
        if networkError.domain == NSURLErrorDomain {
            switch networkError.code {
            case NSURLErrorTimedOut:
                return "模型下载服务器连接超时。请安装包含离线模型的新版 App，无需在手机上下载。"
            case NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed, NSURLErrorNetworkConnectionLost:
                return "无法连接模型下载服务器。请安装包含离线模型的新版 App，或检查网络后重试。"
            default: break
            }
        }
        return error.localizedDescription
    }
}
