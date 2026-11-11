import Foundation
import XCTest
@testable import Prompter

/// Stream a known HTTP body in small delayed chunks, without relying on internet
/// access. A test that only waits for completion would miss the original bug.
private final class StreamingModelURLProtocol: URLProtocol, @unchecked Sendable {
    static let chunk = Data(repeating: 0x5a, count: 65_536)
    static let count = 12
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "speech-download.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global(qos: .utility).async {
            let code = self.request.url?.path == "/missing" ? 404 : 200
            let response = HTTPURLResponse(url: self.request.url!, statusCode: code, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(Self.chunk.count * Self.count)"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for _ in 0..<Self.count {
                Thread.sleep(forTimeInterval: 0.08)
                self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
                if stopped { return }
                self.client?.urlProtocol(self, didLoad: Self.chunk)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    func append(_ bytes: Int64) { lock.lock(); values.append(bytes); lock.unlock() }
    var snapshot: [Int64] { lock.lock(); defer { lock.unlock() }; return values }
}

final class SpeechModelDownloadTests: XCTestCase {
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingModelURLProtocol.self]
        return configuration
    }

    func testReportsReceivedBytesBeforeFileFinishesAndRetainsTemporaryFile() async throws {
        let recorder = ProgressRecorder()
        let downloader = SpeechModelDownloader(configuration: configuration()) { recorder.append($0) }
        let (file, _) = try await downloader.download(from: URL(string: "https://speech-download.test/model")!)
        defer { try? FileManager.default.removeItem(at: file) }
        let total = Int64(StreamingModelURLProtocol.chunk.count * StreamingModelURLProtocol.count)
        XCTAssertTrue(recorder.snapshot.contains { $0 > 0 && $0 < total },
                      "Downloading must produce intermediate progress, not only a final completion")
        XCTAssertEqual(recorder.snapshot.last, total)
        XCTAssertEqual(try Data(contentsOf: file).count, Int(total), "File must outlive the URLSession delegate callback")
    }

    func testCancellationStopsTheActualDownloadTask() async throws {
        let received = expectation(description: "received first bytes")
        received.assertForOverFulfill = false
        let downloader = SpeechModelDownloader(configuration: configuration()) { bytes in
            if bytes > 0 { received.fulfill() }
        }
        let operation = Task { try await downloader.download(from: URL(string: "https://speech-download.test/model")!) }
        await fulfillment(of: [received], timeout: 5)
        operation.cancel()
        do {
            let (file, _) = try await operation.value
            try? FileManager.default.removeItem(at: file)
            XCTFail("Cancelled transfer must not succeed")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    func testHTTPFailureIsReportedInsteadOfInstallingErrorBody() async {
        let downloader = SpeechModelDownloader(configuration: configuration()) { _ in }
        do {
            let (file, _) = try await downloader.download(from: URL(string: "https://speech-download.test/missing")!)
            try? FileManager.default.removeItem(at: file)
            XCTFail("HTTP error bodies must not be accepted as models")
        } catch {
            guard case SpeechModelError.http(404) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testAlreadyCancelledTaskNeverStartsNetworkRequest() async {
        let downloader = SpeechModelDownloader(configuration: configuration()) { _ in XCTFail("No progress after pre-cancellation") }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await downloader.download(from: URL(string: "https://speech-download.test/model")!)
        }
        do {
            let (file, _) = try await operation.value
            try? FileManager.default.removeItem(at: file)
            XCTFail("A cancelled caller must not start a download")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
