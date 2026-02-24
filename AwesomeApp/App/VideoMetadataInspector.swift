import AVFoundation
import Foundation
import UniformTypeIdentifiers
import UIKit

struct VideoMetadataInspector {
    func inspect(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ConversionModelError.noVideoTrack
        }

        async let durationValue = asset.load(.duration)
        async let naturalSizeValue = videoTrack.load(.naturalSize)
        async let preferredTransformValue = videoTrack.load(.preferredTransform)
        async let nominalFrameRateValue = videoTrack.load(.nominalFrameRate)

        let durationSeconds = try await durationValue.seconds
        let naturalSize = try await naturalSizeValue
        let preferredTransform = try await preferredTransformValue
        let nominalFrameRateRaw = try await nominalFrameRateValue

        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let width = max(1, Int(abs(transformedRect.width).rounded()))
        let height = max(1, Int(abs(transformedRect.height).rounded()))
        let frameRate = nominalFrameRateRaw > 0 ? Double(nominalFrameRateRaw) : 30

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        let fileSize = Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)

        return VideoMetadata(
            sourceURL: url,
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSize,
            width: width,
            height: height,
            frameRate: frameRate,
            sourceContainerIdentifier: containerIdentifier(for: url),
            preferredTransform: preferredTransform
        )
    }

    func exportCapabilities(for sourceURL: URL) -> [ConversionPresetCapability] {
        let asset = AVURLAsset(url: sourceURL)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)

        var capabilities: [ConversionPresetCapability] = []
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }

            let fileTypes = session.supportedFileTypes.map(\.rawValue)
            guard !fileTypes.isEmpty else { continue }
            capabilities.append(ConversionPresetCapability(presetName: preset, fileTypeIdentifiers: fileTypes))
        }

        return sortCapabilities(capabilities)
    }

    func generateFirstFramePreview(from url: URL, maxDimension: CGFloat) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: image))
            }
        }
    }

    private func containerIdentifier(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            return utType.identifier
        }
        return ConversionContainer.mov.identifier
    }

    private func sortCapabilities(_ capabilities: [ConversionPresetCapability]) -> [ConversionPresetCapability] {
        let preferredOrder = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPreset640x480,
            AVAssetExportPresetLowQuality,
            AVAssetExportPresetPassthrough
        ]

        return capabilities.sorted { lhs, rhs in
            let leftRank = preferredOrder.firstIndex(of: lhs.presetName) ?? Int.max
            let rightRank = preferredOrder.firstIndex(of: rhs.presetName) ?? Int.max
            if leftRank == rightRank {
                return lhs.presetName < rhs.presetName
            }
            return leftRank < rightRank
        }
    }
}
