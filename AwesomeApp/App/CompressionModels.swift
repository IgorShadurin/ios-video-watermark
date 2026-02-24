import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct VideoMetadata: Equatable {
    let sourceURL: URL
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let width: Int
    let height: Int
    let frameRate: Double
    let sourceContainerIdentifier: String
    let preferredTransform: CGAffineTransform

    var sourceSummary: String {
        let fpsText = Int(frameRate.rounded())
        return "\(width)x\(height) • \(formatSeconds(durationSeconds)) • \(fpsText) fps"
    }
}

struct OutputPresetOption: Identifiable, Hashable {
    static let autoID = "auto"

    let id: String
    let title: String

    var isAuto: Bool {
        id == Self.autoID
    }
}

struct OutputFileTypeOption: Identifiable, Hashable {
    static let autoID = "auto"

    let id: String
    let title: String

    var isAuto: Bool {
        id == Self.autoID
    }
}

enum ConversionModelError: LocalizedError {
    case noVideoTrack
    case noExportCapability

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The selected file does not contain a readable video track."
        case .noExportCapability:
            return "This video cannot be exported with current iOS video frameworks."
        }
    }
}

extension ConversionContainer {
    var avFileType: AVFileType {
        AVFileType(rawValue: identifier)
    }

    var fileExtension: String {
        if let preferred = UTType(identifier)?.preferredFilenameExtension {
            return preferred
        }

        switch identifier {
        case ConversionContainer.mov.identifier:
            return "mov"
        case ConversionContainer.mp4.identifier:
            return "mp4"
        case ConversionContainer.m4v.identifier:
            return "m4v"
        case ConversionContainer.gpp3.identifier:
            return "3gp"
        case ConversionContainer.gpp23.identifier:
            return "3g2"
        default:
            return "mov"
        }
    }

    var label: String {
        switch identifier {
        case ConversionContainer.mov.identifier:
            return "MOV"
        case ConversionContainer.mp4.identifier:
            return "MP4"
        case ConversionContainer.m4v.identifier:
            return "M4V"
        case ConversionContainer.gpp3.identifier:
            return "3GP"
        case ConversionContainer.gpp23.identifier:
            return "3G2"
        default:
            if let utType = UTType(identifier), let ext = utType.preferredFilenameExtension {
                return ext.uppercased()
            }
            return identifier
        }
    }

    init(fileType: AVFileType) {
        self.init(identifier: fileType.rawValue)
    }
}

extension ConversionPresetCapability {
    var shortTitle: String {
        switch presetName {
        case AVAssetExportPresetPassthrough:
            return "Passthrough"
        case AVAssetExportPresetHighestQuality:
            return "Highest"
        case AVAssetExportPresetHEVCHighestQuality:
            return "HEVC Highest"
        case AVAssetExportPresetMediumQuality:
            return "Medium"
        case AVAssetExportPresetLowQuality:
            return "Low"
        case AVAssetExportPreset640x480:
            return "640x480"
        case AVAssetExportPreset960x540:
            return "960x540"
        case AVAssetExportPreset1280x720:
            return "1280x720"
        case AVAssetExportPreset1920x1080:
            return "1080p"
        case AVAssetExportPreset3840x2160:
            return "4K"
        default:
            return presetName.replacingOccurrences(of: "AVAssetExportPreset", with: "")
        }
    }
}

func fileTypeLabel(_ identifier: String) -> String {
    ConversionContainer(identifier: identifier).label
}

func humanReadableSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatSeconds(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0.0s"
    }
    return String(format: "%.1fs", seconds)
}
