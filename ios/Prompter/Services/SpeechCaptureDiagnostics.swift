#if DEBUG
import Foundation

/// Numeric/debug state only: never writes audio or recognized/script text.
/// Persist in Caches so a connected physical device can be diagnosed even when
/// Xcode owns the app's console. This code is absent from release builds.
enum SpeechCaptureDiagnostics {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-speechDiagnostics")
    private static let queue = DispatchQueue(label: "prompter.speech-diagnostics", qos: .utility)
    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let message = message()
        print("[SpeechCapture] \(message)")
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        queue.async {
            let manager = FileManager.default
            guard let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
            let url = cache.appendingPathComponent("SpeechCapture.log")
            do {
                try manager.createDirectory(at: cache, withIntermediateDirectories: true)
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 131_072 {
                    try manager.removeItem(at: url)
                }
                if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch { /* Diagnostics never change capture behavior. */ }
        }
    }
}
#endif
