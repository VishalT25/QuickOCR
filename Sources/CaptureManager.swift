import Foundation
import Vision

final class CaptureManager {
    static let shared = CaptureManager()
    private init() {}

    /// Launches interactive screencapture and returns the temp file path, or nil if cancelled.
    func captureRegion() async -> String? {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".png"

        return await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-s", path]

            proc.terminationHandler = { p in
                let ok = p.terminationStatus == 0
                    && FileManager.default.fileExists(atPath: path)
                    && ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0) > 0
                if ok {
                    continuation.resume(returning: path)
                } else {
                    try? FileManager.default.removeItem(atPath: path)
                    continuation.resume(returning: nil)
                }
            }

            do { try proc.run() } catch {
                try? FileManager.default.removeItem(atPath: path)
                continuation.resume(returning: nil)
            }
        }
    }

    /// Runs Vision OCR on the image at path and returns the extracted text.
    func performOCR(at path: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)
            var resultText = ""
            var resultError: Error?

            let request = VNRecognizeTextRequest { req, error in
                if let error { resultError = error; return }
                let obs = req.results as? [VNRecognizedTextObservation] ?? []
                resultText = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(url: url, options: [:])
            try handler.perform([request])

            if let error = resultError { throw error }
            return resultText
        }.value
    }
}
