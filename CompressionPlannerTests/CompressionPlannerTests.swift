import Foundation
import Testing
@testable import CompressionPlanner

struct CompressionPlannerTests {
    private let planner = VideoConversionPlanner()

    @Test
    func resolvePlanUsesPreferredPresetAndFileType() throws {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetHighestQuality",
                fileTypeIdentifiers: [ConversionContainer.mov.identifier, ConversionContainer.mp4.identifier]
            ),
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetMediumQuality",
                fileTypeIdentifiers: [ConversionContainer.mp4.identifier]
            )
        ]

        let settings = VideoConversionSettings(
            preferredPresetName: "AVAssetExportPresetHighestQuality",
            preferredFileTypeIdentifier: ConversionContainer.mov.identifier,
            optimizeForNetworkUse: true,
            clipStartSeconds: 1,
            clipEndSeconds: 5
        )

        let plan = try planner.resolvePlan(
            sourceDurationSeconds: 10,
            sourceContainerIdentifier: ConversionContainer.mp4.identifier,
            capabilities: capabilities,
            settings: settings
        )

        #expect(plan.presetName == "AVAssetExportPresetHighestQuality")
        #expect(plan.fileTypeIdentifier == ConversionContainer.mov.identifier)
        #expect(plan.clipStartSeconds == 1)
        #expect(plan.clipDurationSeconds == 4)
        #expect(plan.optimizeForNetworkUse)
    }

    @Test
    func resolvePlanAutoPrefersSourceContainerWhenSupported() throws {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetMediumQuality",
                fileTypeIdentifiers: [ConversionContainer.mov.identifier, ConversionContainer.mp4.identifier]
            )
        ]

        let plan = try planner.resolvePlan(
            sourceDurationSeconds: 12,
            sourceContainerIdentifier: ConversionContainer.mov.identifier,
            capabilities: capabilities,
            settings: .default
        )

        #expect(plan.fileTypeIdentifier == ConversionContainer.mov.identifier)
    }

    @Test
    func resolvePlanAutoFallsBackToPreferredOrder() throws {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "CustomPreset",
                fileTypeIdentifiers: [ConversionContainer.gpp3.identifier, ConversionContainer.mp4.identifier]
            )
        ]

        let plan = try planner.resolvePlan(
            sourceDurationSeconds: 8,
            sourceContainerIdentifier: "unknown.container",
            capabilities: capabilities,
            settings: .default
        )

        #expect(plan.fileTypeIdentifier == ConversionContainer.mp4.identifier)
    }

    @Test
    func resolvePlanRejectsUnsupportedPreset() {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetMediumQuality",
                fileTypeIdentifiers: [ConversionContainer.mp4.identifier]
            )
        ]

        let settings = VideoConversionSettings(
            preferredPresetName: "AVAssetExportPresetHighestQuality",
            preferredFileTypeIdentifier: nil,
            optimizeForNetworkUse: true,
            clipStartSeconds: 0,
            clipEndSeconds: nil
        )

        #expect(throws: ConversionPlannerError.unsupportedPreset) {
            try planner.resolvePlan(
                sourceDurationSeconds: 5,
                sourceContainerIdentifier: nil,
                capabilities: capabilities,
                settings: settings
            )
        }
    }

    @Test
    func resolvePlanRejectsUnsupportedFileType() {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetMediumQuality",
                fileTypeIdentifiers: [ConversionContainer.mp4.identifier]
            )
        ]

        let settings = VideoConversionSettings(
            preferredPresetName: nil,
            preferredFileTypeIdentifier: ConversionContainer.mov.identifier,
            optimizeForNetworkUse: true,
            clipStartSeconds: 0,
            clipEndSeconds: nil
        )

        #expect(throws: ConversionPlannerError.unsupportedFileType) {
            try planner.resolvePlan(
                sourceDurationSeconds: 5,
                sourceContainerIdentifier: nil,
                capabilities: capabilities,
                settings: settings
            )
        }
    }

    @Test
    func resolvePlanRejectsInvalidClipRange() {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "AVAssetExportPresetMediumQuality",
                fileTypeIdentifiers: [ConversionContainer.mp4.identifier]
            )
        ]

        let settings = VideoConversionSettings(
            preferredPresetName: nil,
            preferredFileTypeIdentifier: nil,
            optimizeForNetworkUse: true,
            clipStartSeconds: 6,
            clipEndSeconds: 5
        )

        #expect(throws: ConversionPlannerError.invalidClipRange) {
            try planner.resolvePlan(
                sourceDurationSeconds: 10,
                sourceContainerIdentifier: nil,
                capabilities: capabilities,
                settings: settings
            )
        }
    }

    @Test
    func allOutputFileTypesKeepsOrderAndDeduplicates() {
        let capabilities = [
            ConversionPresetCapability(
                presetName: "A",
                fileTypeIdentifiers: [ConversionContainer.mov.identifier, ConversionContainer.mp4.identifier]
            ),
            ConversionPresetCapability(
                presetName: "B",
                fileTypeIdentifiers: [ConversionContainer.mp4.identifier, ConversionContainer.m4v.identifier]
            )
        ]

        let list = planner.allOutputFileTypeIdentifiers(capabilities: capabilities)
        #expect(list == [
            ConversionContainer.mov.identifier,
            ConversionContainer.mp4.identifier,
            ConversionContainer.m4v.identifier
        ])
    }

    @Test
    func workflowHappyPathTransitions() throws {
        var state = ConversionWorkflowState()

        state = try planner.transition(from: state, event: .sourceSelected)
        #expect(state.step == .convert)
        #expect(!state.isConverting)

        state = try planner.transition(from: state, event: .conversionStarted)
        #expect(state.step == .convert)
        #expect(state.isConverting)

        state = try planner.transition(from: state, event: .conversionSucceeded)
        #expect(state.step == .result)
        #expect(!state.isConverting)

        state = try planner.transition(from: state, event: .restart)
        #expect(state.step == .source)
        #expect(!state.isConverting)
    }

    @Test
    func workflowRejectsInvalidTransition() {
        let state = ConversionWorkflowState(step: .source, isConverting: false)

        #expect(throws: ConversionWorkflowError.invalidTransition) {
            _ = try planner.transition(from: state, event: .conversionStarted)
        }

        #expect(throws: ConversionWorkflowError.invalidTransition) {
            _ = try planner.transition(from: state, event: .conversionSucceeded)
        }
    }
}
