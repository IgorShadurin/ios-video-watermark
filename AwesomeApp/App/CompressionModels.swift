import AVFoundation
import CoreGraphics
import Foundation
import UIKit

struct WatermarkSourceVideo: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let width: Int
    let height: Int
    let frameRate: Double
    let sourceContainerIdentifier: String
    let preferredTransform: CGAffineTransform

    init(
        sourceURL: URL,
        durationSeconds: Double,
        fileSizeBytes: Int64,
        width: Int,
        height: Int,
        frameRate: Double,
        sourceContainerIdentifier: String,
        preferredTransform: CGAffineTransform
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.sourceContainerIdentifier = sourceContainerIdentifier
        self.preferredTransform = preferredTransform
    }

    var sourceSummary: String {
        "\(width)x\(height) • \(formatSeconds(durationSeconds)) • \(Int(frameRate.rounded())) fps"
    }
}

struct QueuedWatermarkVideo: Identifiable, Equatable {
    let id = UUID()
    let source: WatermarkSourceVideo
    let previewImage: UIImage?

    var name: String {
        source.sourceURL.lastPathComponent
    }

    var title: String {
        source.sourceSummary
    }

    var sizeText: String {
        humanReadableSize(source.fileSizeBytes)
    }
}

struct WatermarkResult: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let outputURL: URL
    let outputSizeBytes: Int64
}

enum WatermarkPositionPreset: String, CaseIterable, Identifiable, Codable, Hashable {
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .top: return "Top"
        case .topRight: return "Top Right"
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom Right"
        case .custom: return "Custom"
        }
    }

    var defaultPosition: (Double, Double) {
        switch self {
        case .topLeft: return (0, 100)
        case .top: return (50, 100)
        case .topRight: return (100, 100)
        case .left: return (0, 50)
        case .center: return (50, 50)
        case .right: return (100, 50)
        case .bottomLeft: return (0, 0)
        case .bottom: return (50, 0)
        case .bottomRight: return (100, 0)
        case .custom: return (12, 12)
        }
    }
}

struct WatermarkSettings: Codable, Equatable, Sendable {
    var sizePercent: Double
    var opacity: Double
    var positionPreset: WatermarkPositionPreset
    var positionXPercent: Double
    var positionYPercent: Double

    init(
        sizePercent: Double,
        opacity: Double,
        positionPreset: WatermarkPositionPreset,
        positionXPercent: Double,
        positionYPercent: Double
    ) {
        self.sizePercent = WatermarkSettings.clamp(sizePercent, min: 5, max: 60)
        self.opacity = WatermarkSettings.clamp(opacity, min: 0.05, max: 1)
        self.positionPreset = positionPreset
        self.positionXPercent = WatermarkSettings.clamp(positionXPercent, min: 0, max: 100)
        self.positionYPercent = WatermarkSettings.clamp(positionYPercent, min: 0, max: 100)
    }

    static var defaultSettings: WatermarkSettings {
        WatermarkSettings(
            sizePercent: 18,
            opacity: 0.85,
            positionPreset: .bottomRight,
            positionXPercent: 94,
            positionYPercent: 6
        )
    }

    func appliedPreset(_ preset: WatermarkPositionPreset) -> WatermarkSettings {
        let defaults = preset.defaultPosition
        var next = self
        next.positionPreset = preset
        next.positionXPercent = defaults.0
        next.positionYPercent = defaults.1
        return next
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(minValue(value, min), maxValue(value, max))
    }

    private static func minValue(_ value: Double, _ minimum: Double) -> Double {
        Swift.max(value, minimum)
    }

    private static func maxValue(_ value: Double, _ maximum: Double) -> Double {
        Swift.min(value, maximum)
    }
}

enum ConversionWorkflowStep: String, Equatable, Codable, Sendable {
    case source
    case convert
    case result
}

struct ConversionWorkflowState: Equatable, Codable, Sendable {
    var step: ConversionWorkflowStep
    var isConverting: Bool

    init(step: ConversionWorkflowStep = .source, isConverting: Bool = false) {
        self.step = step
        self.isConverting = isConverting
    }
}

enum ConversionWorkflowEvent: Equatable, Sendable {
    case sourceSelected
    case sourceCleared
    case conversionStarted
    case conversionSucceeded
    case conversionFailed
    case restart
}

enum ConversionWorkflowError: Error, Equatable, LocalizedError {
    case invalidTransition

    var errorDescription: String? {
        "This workflow transition is not valid right now."
    }
}

enum WatermarkSourceError: LocalizedError {
    case noVideoTrack
    case noValidExportPath
    case cannotCompose
    case cancelled
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The selected file does not include a readable video track."
        case .noValidExportPath:
            return "Unable to create a valid output file path."
        case .cannotCompose:
            return "Unable to prepare composition for this video."
        case .cancelled:
            return "Watermarking was cancelled."
        case .unsupported:
            return "This format is not supported on this device."
        }
    }
}

func humanReadableSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatSeconds(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0.0s" }
    return String(format: "%.1fs", seconds)
}
