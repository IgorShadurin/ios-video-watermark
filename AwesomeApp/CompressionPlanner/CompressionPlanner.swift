import Foundation

public struct ConversionContainer: Hashable, Codable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public static let mov = ConversionContainer(identifier: "com.apple.quicktime-movie")
    public static let mp4 = ConversionContainer(identifier: "public.mpeg-4")
    public static let m4v = ConversionContainer(identifier: "com.apple.m4v-video")
    public static let gpp3 = ConversionContainer(identifier: "public.3gpp")
    public static let gpp23 = ConversionContainer(identifier: "public.3gpp2")

    public static let preferredAutoOrder: [ConversionContainer] = [.mp4, .mov, .m4v, .gpp3, .gpp23]
}

public struct ConversionPresetCapability: Hashable, Codable, Sendable {
    public let presetName: String
    public let fileTypeIdentifiers: [String]

    public init(presetName: String, fileTypeIdentifiers: [String]) {
        self.presetName = presetName
        self.fileTypeIdentifiers = fileTypeIdentifiers
    }
}

public struct VideoConversionSettings: Equatable, Codable, Sendable {
    public var preferredPresetName: String?
    public var preferredFileTypeIdentifier: String?
    public var optimizeForNetworkUse: Bool
    public var clipStartSeconds: Double
    public var clipEndSeconds: Double?

    public init(
        preferredPresetName: String?,
        preferredFileTypeIdentifier: String?,
        optimizeForNetworkUse: Bool,
        clipStartSeconds: Double,
        clipEndSeconds: Double?
    ) {
        self.preferredPresetName = preferredPresetName
        self.preferredFileTypeIdentifier = preferredFileTypeIdentifier
        self.optimizeForNetworkUse = optimizeForNetworkUse
        self.clipStartSeconds = clipStartSeconds
        self.clipEndSeconds = clipEndSeconds
    }

    public static let `default` = VideoConversionSettings(
        preferredPresetName: nil,
        preferredFileTypeIdentifier: nil,
        optimizeForNetworkUse: true,
        clipStartSeconds: 0,
        clipEndSeconds: nil
    )
}

public struct ConversionPlan: Equatable, Sendable {
    public let presetName: String
    public let fileTypeIdentifier: String
    public let clipStartSeconds: Double
    public let clipDurationSeconds: Double
    public let optimizeForNetworkUse: Bool
    public let reason: String

    public init(
        presetName: String,
        fileTypeIdentifier: String,
        clipStartSeconds: Double,
        clipDurationSeconds: Double,
        optimizeForNetworkUse: Bool,
        reason: String
    ) {
        self.presetName = presetName
        self.fileTypeIdentifier = fileTypeIdentifier
        self.clipStartSeconds = clipStartSeconds
        self.clipDurationSeconds = clipDurationSeconds
        self.optimizeForNetworkUse = optimizeForNetworkUse
        self.reason = reason
    }
}

public enum ConversionPlannerError: Error, Equatable, LocalizedError {
    case noPresetCapabilities
    case invalidSourceDuration
    case invalidClipRange
    case unsupportedPreset
    case unsupportedFileType

    public var errorDescription: String? {
        switch self {
        case .noPresetCapabilities:
            return "No compatible export presets are available for this source video."
        case .invalidSourceDuration:
            return "The source duration is invalid."
        case .invalidClipRange:
            return "The selected clip range is invalid."
        case .unsupportedPreset:
            return "The selected export preset is not supported for this video."
        case .unsupportedFileType:
            return "The selected output format is not supported for the chosen preset."
        }
    }
}

public struct VideoConversionPlanner {
    public init() {}

    public func resolvePlan(
        sourceDurationSeconds: Double,
        sourceContainerIdentifier: String?,
        capabilities: [ConversionPresetCapability],
        settings: VideoConversionSettings
    ) throws -> ConversionPlan {
        guard sourceDurationSeconds > 0 else {
            throw ConversionPlannerError.invalidSourceDuration
        }

        guard !capabilities.isEmpty else {
            throw ConversionPlannerError.noPresetCapabilities
        }

        let clipStart = max(0, settings.clipStartSeconds)
        let clipEndCandidate = settings.clipEndSeconds ?? sourceDurationSeconds
        let clipEnd = min(sourceDurationSeconds, clipEndCandidate)
        guard clipEnd > clipStart else {
            throw ConversionPlannerError.invalidClipRange
        }

        let capability = try selectPreset(capabilities: capabilities, preferredPresetName: settings.preferredPresetName)
        let fileTypeIdentifier = try selectFileType(
            capability: capability,
            preferredFileTypeIdentifier: settings.preferredFileTypeIdentifier,
            sourceContainerIdentifier: sourceContainerIdentifier
        )

        return ConversionPlan(
            presetName: capability.presetName,
            fileTypeIdentifier: fileTypeIdentifier,
            clipStartSeconds: clipStart,
            clipDurationSeconds: clipEnd - clipStart,
            optimizeForNetworkUse: settings.optimizeForNetworkUse,
            reason: "Resolved from source-compatible presets and file types"
        )
    }

    public func allOutputFileTypeIdentifiers(capabilities: [ConversionPresetCapability]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for capability in capabilities {
            for type in capability.fileTypeIdentifiers where !seen.contains(type) {
                seen.insert(type)
                ordered.append(type)
            }
        }
        return ordered
    }

    public func transition(
        from state: ConversionWorkflowState,
        event: ConversionWorkflowEvent
    ) throws -> ConversionWorkflowState {
        switch event {
        case .sourceSelected:
            return ConversionWorkflowState(step: .convert, isConverting: false)
        case .sourceCleared:
            return ConversionWorkflowState(step: .source, isConverting: false)
        case .conversionStarted:
            guard state.step == .convert, !state.isConverting else {
                throw ConversionWorkflowError.invalidTransition
            }
            return ConversionWorkflowState(step: .convert, isConverting: true)
        case .conversionSucceeded:
            guard state.isConverting else {
                throw ConversionWorkflowError.invalidTransition
            }
            return ConversionWorkflowState(step: .result, isConverting: false)
        case .conversionFailed:
            guard state.isConverting else {
                throw ConversionWorkflowError.invalidTransition
            }
            return ConversionWorkflowState(step: .convert, isConverting: false)
        case .restart:
            return ConversionWorkflowState(step: .source, isConverting: false)
        }
    }

    private func selectPreset(
        capabilities: [ConversionPresetCapability],
        preferredPresetName: String?
    ) throws -> ConversionPresetCapability {
        if let preferredPresetName {
            guard let preferred = capabilities.first(where: { $0.presetName == preferredPresetName }) else {
                throw ConversionPlannerError.unsupportedPreset
            }
            return preferred
        }

        let preferredOrder = [
            "AVAssetExportPresetHEVCHighestQuality",
            "AVAssetExportPresetHighestQuality",
            "AVAssetExportPresetMediumQuality",
            "AVAssetExportPreset640x480",
            "AVAssetExportPresetLowQuality",
            "AVAssetExportPresetPassthrough"
        ]

        for preset in preferredOrder {
            if let matched = capabilities.first(where: { $0.presetName == preset }) {
                return matched
            }
        }

        return capabilities[0]
    }

    private func selectFileType(
        capability: ConversionPresetCapability,
        preferredFileTypeIdentifier: String?,
        sourceContainerIdentifier: String?
    ) throws -> String {
        guard !capability.fileTypeIdentifiers.isEmpty else {
            throw ConversionPlannerError.unsupportedFileType
        }

        if let preferredFileTypeIdentifier {
            guard capability.fileTypeIdentifiers.contains(preferredFileTypeIdentifier) else {
                throw ConversionPlannerError.unsupportedFileType
            }
            return preferredFileTypeIdentifier
        }

        if let sourceContainerIdentifier,
           capability.fileTypeIdentifiers.contains(sourceContainerIdentifier) {
            return sourceContainerIdentifier
        }

        for preferred in ConversionContainer.preferredAutoOrder {
            if capability.fileTypeIdentifiers.contains(preferred.identifier) {
                return preferred.identifier
            }
        }

        return capability.fileTypeIdentifiers[0]
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
        "The requested workflow transition is invalid for the current state."
    }
}
