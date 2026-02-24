import AVFoundation
import CoreImage
import QuartzCore
import Foundation
import UIKit

final class VideoConversionService {
    enum VideoConversionServiceError: LocalizedError {
        case cannotCreateExportSession
        case unsupportedFileType
        case missingOutput
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cannotCreateExportSession:
                return "Cannot create the video export pipeline."
            case .unsupportedFileType:
                return "Selected output format is not supported for this source video."
            case .missingOutput:
                return "Export completed without an output file."
            case .cancelled:
                return "Export was cancelled."
            }
        }
    }

    private struct ActiveSession {
        let session: AVAssetExportSession
        let outputURL: URL
    }

    private let lock = NSLock()
    private var activeSessions: [UUID: ActiveSession] = [:]

    func cancelCurrentConversion() {
        let sessions = lock.withLock {
            let list = Array(activeSessions.values)
            activeSessions.removeAll()
            return list
        }

        sessions.forEach { active in
            active.session.cancelExport()
            try? FileManager.default.removeItem(at: active.outputURL)
        }
    }

    func applyWatermarkBatch(
        sourceURLs: [URL],
        watermarkImage: UIImage,
        settings: WatermarkSettings,
        outputFileType: AVFileType = .mp4,
        progressHandler: ((Int, Int, Double) -> Void)? = nil
    ) async throws -> [URL] {
        var outputs: [URL] = []
        outputs.reserveCapacity(sourceURLs.count)

        for (index, sourceURL) in sourceURLs.enumerated() {
            if Task.isCancelled {
                throw WatermarkSourceError.cancelled
            }

            let fileURL = try await applyWatermark(
                sourceURL: sourceURL,
                watermarkImage: watermarkImage,
                settings: settings,
                outputFileType: outputFileType
            )
            outputs.append(fileURL)

            let done = index + 1
            let progress = Double(done) / Double(sourceURLs.count)
            progressHandler?(done, sourceURLs.count, progress)
        }

        return outputs
    }

    func applyWatermark(
        sourceURL: URL,
        watermarkImage: UIImage,
        settings: WatermarkSettings,
        outputFileType: AVFileType = .mp4
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = tracks.first else {
            throw WatermarkSourceError.noVideoTrack
        }

        let composition = AVMutableComposition()
        guard
            let sourceDuration = try? await asset.load(.duration),
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw WatermarkSourceError.cannotCompose
        }

        let sourceRange = CMTimeRange(start: .zero, duration: sourceDuration)
        try compositionVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: .zero)

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioRange = CMTimeRange(start: .zero, duration: sourceDuration)
            try compositionAudioTrack.insertTimeRange(audioRange, of: audioTrack, at: .zero)
        }

        let transform = try await sourceVideoTrack.load(.preferredTransform)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)

        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderWidth = max(1, abs(Int(transformedRect.width.rounded())))
        let renderHeight = max(1, abs(Int(transformedRect.height.rounded())))

        let frameDuration = CMTime(value: 1, timescale: 30)
        let instructions = AVMutableVideoCompositionInstruction()
        instructions.timeRange = sourceRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instructions.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = [instructions]

        let watermarkLayer = CALayer()
        guard let watermarkCG = watermarkImage.cgImage else {
            throw WatermarkSourceError.unsupported
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize)

        let contentLayer = CALayer()
        contentLayer.frame = parentLayer.frame
        parentLayer.addSublayer(contentLayer)

        let sizeRatio = max(0.001, settings.sizePercent) / 100
        let watermarkBaseWidth = videoComposition.renderSize.width * CGFloat(sizeRatio)
        let sourceRatio = watermarkImage.size.width > 0 ? watermarkImage.size.width / watermarkImage.size.height : 1

        var overlayWidth = watermarkBaseWidth
        var overlayHeight = sourceRatio > 0 ? overlayWidth / sourceRatio : overlayWidth
        let maxOverlayWidth = videoComposition.renderSize.width * 0.9
        let maxOverlayHeight = videoComposition.renderSize.height * 0.25

        if overlayWidth > maxOverlayWidth {
            overlayWidth = maxOverlayWidth
            overlayHeight = sourceRatio > 0 ? overlayWidth / sourceRatio : overlayWidth
        }

        if overlayHeight > maxOverlayHeight {
            overlayHeight = maxOverlayHeight
            overlayWidth = sourceRatio > 0 ? overlayHeight * sourceRatio : overlayHeight
        }

        overlayWidth = max(18, overlayWidth)
        overlayHeight = max(18 * (overlayHeight / max(overlayWidth, 1)), 18)

        let maxX = max(0, videoComposition.renderSize.width - overlayWidth)
        let maxY = max(0, videoComposition.renderSize.height - overlayHeight)

        watermarkLayer.contents = watermarkCG
        watermarkLayer.contentsScale = UIScreen.main.scale
        watermarkLayer.opacity = Float(settings.opacity)
        watermarkLayer.frame = CGRect(
            x: maxX * CGFloat(settings.positionXPercent) / 100,
            y: maxY * (1 - CGFloat(settings.positionYPercent) / 100),
            width: overlayWidth,
            height: overlayHeight
        )
        watermarkLayer.shouldRasterize = true
        watermarkLayer.rasterizationScale = UIScreen.main.scale
        parentLayer.addSublayer(watermarkLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: contentLayer,
            in: parentLayer
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoConversionServiceError.cannotCreateExportSession
        }

        exportSession.videoComposition = videoComposition

        let supportedType = supportedOutputType(session: exportSession, preferred: outputFileType)
        guard exportSession.supportedFileTypes.contains(supportedType) else {
            throw VideoConversionServiceError.unsupportedFileType
        }

        let outputURL = makeOutputURL(fileType: supportedType)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = supportedType
        exportSession.shouldOptimizeForNetworkUse = true

        let sessionID = UUID()
        register(sessionID: sessionID, session: exportSession, outputURL: outputURL)
        defer { unregister(sessionID: sessionID) }

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    guard fileManager.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: VideoConversionServiceError.missingOutput)
                        return
                    }
                    continuation.resume(returning: outputURL)
                case .cancelled:
                    try? fileManager.removeItem(at: outputURL)
                    continuation.resume(throwing: VideoConversionServiceError.cancelled)
                case .failed:
                    try? fileManager.removeItem(at: outputURL)
                    continuation.resume(throwing: exportSession.error ?? WatermarkSourceError.unsupported)
                default:
                    try? fileManager.removeItem(at: outputURL)
                    continuation.resume(throwing: exportSession.error ?? WatermarkSourceError.cannotCompose)
                }
            }
        }
    }

    private func supportedOutputType(session: AVAssetExportSession, preferred: AVFileType) -> AVFileType {
        if session.supportedFileTypes.contains(preferred) {
            return preferred
        }
        if session.supportedFileTypes.contains(.mp4) { return .mp4 }
        if session.supportedFileTypes.contains(.mov) { return .mov }
        return session.supportedFileTypes.first ?? preferred
    }

    private func makeOutputURL(fileType: AVFileType) -> URL {
        let ext = UTType(fileType.rawValue)?.preferredFilenameExtension ?? "mp4"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("watermarked-video-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    private func register(sessionID: UUID, session: AVAssetExportSession, outputURL: URL) {
        lock.lock()
        activeSessions[sessionID] = ActiveSession(session: session, outputURL: outputURL)
        lock.unlock()
    }

    private func unregister(sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions.removeValue(forKey: sessionID)
    }
}

private extension NSLock {
    func withLock<T>(_ execute: () -> T) -> T {
        lock()
        defer { unlock() }
        return execute()
    }
}
