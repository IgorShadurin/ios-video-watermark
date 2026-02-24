import AVFoundation
import Foundation
import UniformTypeIdentifiers
import UIKit

struct VideoMetadataInspector {
    func inspect(url: URL) async throws -> WatermarkSourceVideo {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw WatermarkSourceError.noVideoTrack
        }

        async let duration = asset.load(.duration)
        async let naturalSize = videoTrack.load(.naturalSize)
        async let preferredTransform = videoTrack.load(.preferredTransform)
        async let nominalFrameRateTask = videoTrack.load(.nominalFrameRate)

        let durationSeconds = try await duration.seconds
        let nominalFrameRate = try await nominalFrameRateTask
        let frameRate = max(1.0, Double(nominalFrameRate))
        let transform = try await preferredTransform
        let rawSize = try await naturalSize

        let renderRect = CGRect(origin: .zero, size: rawSize).applying(transform)
        let width = max(1, Int(round(abs(renderRect.width))))
        let height = max(1, Int(round(abs(renderRect.height))))

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        let size = Int64(resourceValues.fileSize ?? resourceValues.fileAllocatedSize ?? 0)

        return WatermarkSourceVideo(
            sourceURL: url,
            durationSeconds: durationSeconds,
            fileSizeBytes: size,
            width: width,
            height: height,
            frameRate: frameRate,
            sourceContainerIdentifier: containerIdentifier(for: url),
            preferredTransform: transform
        )
    }

    func generateFirstFramePreview(from url: URL, maxDimension: CGFloat) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.appliesPreferredTrackTransform = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            generator.generateCGImageAsynchronously(for: .zero) { image, _ , _ in
                continuation.resume(returning: image.flatMap { UIImage(cgImage: $0) })
            }
        }
    }

    func preferredExportType(for asset: AVAsset) -> AVFileType {
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        for preset in [AVAssetExportPresetHighestQuality] {
            if presets.contains(preset), let session = AVAssetExportSession(asset: asset, presetName: preset) {
                if session.supportedFileTypes.contains(.mp4) {
                    return .mp4
                }
                if let type = session.supportedFileTypes.first {
                    return type
                }
            }
        }
        return .mp4
    }

    private func containerIdentifier(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            return utType.identifier
        }
        return "public.mpeg-4"
    }
}
