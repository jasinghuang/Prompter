import Foundation

/// Use the session's download delegate, rather than the async convenience API's
/// task delegate. The latter does not deliver download-specific progress events.
/// All delegate callbacks are serialized; the lock also covers task cancellation.
final class SpeechModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    init(configuration: URLSessionConfiguration = .ephemeral,
         progress: @escaping @Sendable (Int64) -> Void) {
        self.configuration = configuration
        self.progress = progress
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                queue.qualityOfService = .utility
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                // Resume under the same lock so cancellation cannot miss a task
                // created between the cancellation check and its assignment.
                task.resume()
                lock.unlock()
            }
        } onCancel: { self.cancel() }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let session = session
        self.session = nil
        task = nil
        lock.unlock()
        if let continuation { continuation.resume(with: result) }
        else if case .success(let (url, _)) = result { try? FileManager.default.removeItem(at: url) }
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
            finish(.failure(SpeechModelError.http((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)))
            return
        }
        // URLSession deletes its temporary file after this callback returns. Move
        // it before resuming the async caller, which may run on another executor.
        let retained = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID())")
        do {
            try FileManager.default.moveItem(at: location, to: retained)
            finish(.success((retained, response)))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
