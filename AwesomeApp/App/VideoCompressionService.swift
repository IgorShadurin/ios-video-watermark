import AVFoundation
import Foundation

enum VideoConversionServiceError: LocalizedError {
    case cannotCreateExportSession
    case unsupportedFileType
    case missingOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotCreateExportSession:
            return "Unable to initialize export session for this video and preset."
        case .unsupportedFileType:
            return "The selected output format is unsupported for this preset."
        case .missingOutput:
            return "Conversion finished without a valid output file."
        case .cancelled:
            return "Conversion was cancelled."
        }
    }
}

final class VideoConversionService {
    private struct ActiveConversion {
        let session: AVAssetExportSession
        let outputURL: URL
    }

    private let lock = NSLock()
    private var activeConversion: ActiveConversion?

    func cancelCurrentConversion() {
        let conversion: ActiveConversion? = {
            lock.lock()
            defer { lock.unlock() }
            return activeConversion
        }()

        guard let conversion else { return }
        conversion.session.cancelExport()
        try? FileManager.default.removeItem(at: conversion.outputURL)
    }

    func convert(
        sourceURL: URL,
        plan: ConversionPlan,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: plan.presetName) else {
            throw VideoConversionServiceError.cannotCreateExportSession
        }

        let outputFileType = AVFileType(rawValue: plan.fileTypeIdentifier)
        guard session.supportedFileTypes.contains(outputFileType) else {
            throw VideoConversionServiceError.unsupportedFileType
        }

        let outputURL = makeOutputURL(fileTypeIdentifier: plan.fileTypeIdentifier)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        session.outputURL = outputURL
        session.outputFileType = outputFileType
        session.shouldOptimizeForNetworkUse = plan.optimizeForNetworkUse

        let start = CMTime(seconds: plan.clipStartSeconds, preferredTimescale: 600)
        let duration = CMTime(seconds: plan.clipDurationSeconds, preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, duration: duration)

        registerActiveConversion(session: session, outputURL: outputURL)
        defer { clearActiveConversion(outputURL: outputURL) }

        var progressTask: Task<Void, Never>?
        progressTask = Task {
            while !Task.isCancelled {
                let status = session.status
                if status == .exporting || status == .waiting {
                    progressHandler?(Double(session.progress))
                }
                if status == .completed || status == .cancelled || status == .failed {
                    break
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        do {
            let resultURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                session.exportAsynchronously {
                    progressTask?.cancel()

                    switch session.status {
                    case .completed:
                        guard fileManager.fileExists(atPath: outputURL.path) else {
                            continuation.resume(throwing: VideoConversionServiceError.missingOutput)
                            return
                        }
                        progressHandler?(1.0)
                        continuation.resume(returning: outputURL)
                    case .failed:
                        try? fileManager.removeItem(at: outputURL)
                        continuation.resume(throwing: session.error ?? VideoConversionServiceError.missingOutput)
                    case .cancelled:
                        try? fileManager.removeItem(at: outputURL)
                        continuation.resume(throwing: VideoConversionServiceError.cancelled)
                    default:
                        try? fileManager.removeItem(at: outputURL)
                        continuation.resume(throwing: session.error ?? VideoConversionServiceError.missingOutput)
                    }
                }
            }

            return resultURL
        } catch {
            progressTask?.cancel()
            throw error
        }
    }

    private func registerActiveConversion(session: AVAssetExportSession, outputURL: URL) {
        lock.lock()
        activeConversion = ActiveConversion(session: session, outputURL: outputURL)
        lock.unlock()
    }

    private func clearActiveConversion(outputURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard activeConversion?.outputURL == outputURL else { return }
        activeConversion = nil
    }

    private func makeOutputURL(fileTypeIdentifier: String) -> URL {
        let container = ConversionContainer(identifier: fileTypeIdentifier)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("converted-video-\(UUID().uuidString)")
            .appendingPathExtension(container.fileExtension)
    }
}
