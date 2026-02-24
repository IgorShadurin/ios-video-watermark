import CoreGraphics
import Foundation

public struct WatermarkLayoutRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WatermarkSettings: Equatable, Codable, Sendable {
    public var sizePercent: Double
    public var opacity: Double
    public var positionXPercent: Double
    public var positionYPercent: Double

    public init(sizePercent: Double, opacity: Double, positionXPercent: Double, positionYPercent: Double) {
        self.sizePercent = WatermarkSettings.clamp(sizePercent, min: 5, max: 60)
        self.opacity = WatermarkSettings.clamp(opacity, min: 0.05, max: 1)
        self.positionXPercent = WatermarkSettings.clamp(positionXPercent, min: 0, max: 100)
        self.positionYPercent = WatermarkSettings.clamp(positionYPercent, min: 0, max: 100)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

public enum WatermarkPlannerError: Error, Equatable, LocalizedError {
    case invalidSourceSize
    case invalidWatermarkSize

    public var errorDescription: String? {
        switch self {
        case .invalidSourceSize:
            return "Source dimensions are invalid."
        case .invalidWatermarkSize:
            return "Watermark image dimensions are invalid."
        }
    }
}

public struct WatermarkPlanner {
    public init() {}

    public func resolveLayout(
        sourceWidth: Double,
        sourceHeight: Double,
        watermarkImageWidth: Double,
        watermarkImageHeight: Double,
        settings: WatermarkSettings
    ) throws -> WatermarkLayoutRect {
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw WatermarkPlannerError.invalidSourceSize
        }
        guard watermarkImageWidth > 0, watermarkImageHeight > 0 else {
            throw WatermarkPlannerError.invalidWatermarkSize
        }

        let overlayWidth = sourceWidth * (settings.sizePercent / 100)
        let sourceAspect = watermarkImageWidth / watermarkImageHeight
        var width = overlayWidth
        var height = sourceAspect > 0 ? overlayWidth / sourceAspect : overlayWidth

        if width > sourceWidth * 0.9 {
            width = sourceWidth * 0.9
            height = sourceAspect > 0 ? width / sourceAspect : width
        }
        if height > sourceHeight * 0.25 {
            height = sourceHeight * 0.25
            width = sourceAspect > 0 ? height * sourceAspect : height
        }

        let clampedWidth = max(18, width)
        let clampedHeight = max(18, height)

        let maxX = max(0, sourceWidth - clampedWidth)
        let maxY = max(0, sourceHeight - clampedHeight)
        let x = maxX * settings.positionXPercent / 100
        let y = maxY * (1 - settings.positionYPercent / 100)

        return WatermarkLayoutRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }
}

public enum ConversionWorkflowStep: String, Equatable, Codable, Sendable {
    case source
    case convert
    case result
}

public struct ConversionWorkflowState: Equatable, Codable, Sendable {
    public var step: ConversionWorkflowStep
    public var isConverting: Bool

    public init(step: ConversionWorkflowStep = .source, isConverting: Bool = false) {
        self.step = step
        self.isConverting = isConverting
    }
}

public enum ConversionWorkflowEvent: Equatable, Sendable {
    case sourceSelected
    case sourceCleared
    case conversionStarted
    case conversionSucceeded
    case conversionFailed
    case restart
}

public enum ConversionWorkflowError: Error, Equatable, LocalizedError {
    case invalidTransition

    public var errorDescription: String? {
        "This workflow transition is not valid right now."
    }
}
