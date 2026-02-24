import Combine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class VideoConversionViewModel: ObservableObject {
    private enum SourceLoadError: LocalizedError {
        case noVideoSelected

        var errorDescription: String? {
            switch self {
            case .noVideoSelected:
                return "No video was selected."
            }
        }
    }

    @Published var pickerItem: PhotosPickerItem?

    @Published var selectedPresetID: String = OutputPresetOption.autoID {
        didSet {
            if selectedPresetID != oldValue {
                ensureSelectedFileTypeIsSupported()
            }
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published var selectedFileTypeID: String = OutputFileTypeOption.autoID {
        didSet {
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published var optimizeForNetworkUse: Bool = true {
        didSet {
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published var clipStartSeconds: Double = 0 {
        didSet {
            normalizeClipRange()
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published var useClipEnd: Bool = false {
        didSet {
            normalizeClipRange()
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published var clipEndSeconds: Double = 0 {
        didSet {
            normalizeClipRange()
            persistSettingsIfNeeded()
            validateCurrentPlan()
        }
    }

    @Published private(set) var workflowStep: ConversionWorkflowStep = .source
    @Published private(set) var sourceMetadata: VideoMetadata?
    @Published private(set) var sourcePreviewImage: UIImage?
    @Published private(set) var capabilities: [ConversionPresetCapability] = []
    @Published private(set) var convertedVideoURL: URL?
    @Published private(set) var convertedFileSizeBytes: Int64?

    @Published private(set) var statusMessage: String = "Pick a video from Photos or Files to begin."
    @Published private(set) var errorMessage: String?
    @Published private(set) var validationMessage: String?
    @Published private(set) var isLoadingSourceDetails = false
    @Published private(set) var isConverting = false
    @Published private(set) var isCancellingConversion = false
    @Published private(set) var conversionProgress: Double?

    private let settingsStore = ConversionSettingsStore()
    private let metadataInspector = VideoMetadataInspector()
    private let conversionService = VideoConversionService()
    private let planner = VideoConversionPlanner()

    private var isRestoringDraftSettings = false
    private var workflowState = ConversionWorkflowState()

    init() {
        restoreSettings()
        applyShowcaseStateIfNeeded()
    }

    var presetOptions: [OutputPresetOption] {
        var options: [OutputPresetOption] = [
            OutputPresetOption(id: OutputPresetOption.autoID, title: "Auto")
        ]

        for capability in capabilities {
            options.append(OutputPresetOption(id: capability.presetName, title: capability.shortTitle))
        }
        return options
    }

    var fileTypeOptions: [OutputFileTypeOption] {
        var options: [OutputFileTypeOption] = [
            OutputFileTypeOption(id: OutputFileTypeOption.autoID, title: "Auto")
        ]

        let identifiers: [String]
        if selectedPresetID == OutputPresetOption.autoID {
            identifiers = planner.allOutputFileTypeIdentifiers(capabilities: capabilities)
        } else if let capability = capabilities.first(where: { $0.presetName == selectedPresetID }) {
            identifiers = capability.fileTypeIdentifiers
        } else {
            identifiers = []
        }

        for identifier in identifiers {
            options.append(OutputFileTypeOption(id: identifier, title: fileTypeLabel(identifier)))
        }

        return options
    }

    var sourceSummaryText: String? {
        sourceMetadata?.sourceSummary
    }

    var sourceSizeText: String? {
        guard let sourceMetadata else { return nil }
        return humanReadableSize(sourceMetadata.fileSizeBytes)
    }

    var outputSizeText: String? {
        guard let convertedFileSizeBytes else { return nil }
        return humanReadableSize(convertedFileSizeBytes)
    }

    var clipDurationRange: ClosedRange<Double> {
        let duration = sourceMetadata?.durationSeconds ?? 0
        return 0...max(duration, 0)
    }

    var canConvert: Bool {
        sourceMetadata != nil && !isLoadingSourceDetails && !isConverting && validationMessage == nil
    }

    var canCancelConversion: Bool {
        isConverting && !isCancellingConversion
    }

    var canSaveResult: Bool {
        convertedVideoURL != nil && !isConverting
    }

    var conversionProgressText: String? {
        guard let conversionProgress else { return nil }
        return "\(Int((conversionProgress * 100).rounded()))%"
    }

    var planSummaryText: String? {
        guard let plan = try? currentPlan() else {
            return nil
        }
        return "Preset: \(presetTitle(plan.presetName)) • Format: \(fileTypeLabel(plan.fileTypeIdentifier))"
    }

    func handlePickerChange() async {
        guard let pickerItem else { return }

        isLoadingSourceDetails = true
        errorMessage = nil
        statusMessage = "Loading selected video..."

        do {
            guard let picked = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
                throw SourceLoadError.noVideoSelected
            }
            try await loadSource(from: picked.url)
        } catch {
            isLoadingSourceDetails = false
            statusMessage = "Failed to load source video."
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedFile(url: URL) async {
        isLoadingSourceDetails = true
        errorMessage = nil
        statusMessage = "Loading imported file..."

        do {
            let localURL = try copyImportedVideoToTemporaryLocation(from: url)
            try await loadSource(from: localURL)
        } catch {
            isLoadingSourceDetails = false
            statusMessage = "Failed to load imported file."
            errorMessage = error.localizedDescription
        }
    }

    func handleImportFailure(_ message: String) {
        errorMessage = "File import failed: \(message)"
    }

    func convert() async {
        guard let sourceMetadata else {
            errorMessage = "Pick a source video first."
            return
        }

        let plan: ConversionPlan
        do {
            plan = try currentPlan()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            workflowState = try planner.transition(from: workflowState, event: .conversionStarted)
            applyWorkflowState()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isConverting = true
        isCancellingConversion = false
        conversionProgress = 0
        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        errorMessage = nil
        statusMessage = "Converting video..."

        do {
            let outputURL = try await conversionService.convert(
                sourceURL: sourceMetadata.sourceURL,
                plan: plan,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.conversionProgress = progress
                    }
                }
            )

            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
            let size = Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)

            workflowState = try planner.transition(from: workflowState, event: .conversionSucceeded)
            applyWorkflowState()
            convertedVideoURL = outputURL
            convertedFileSizeBytes = size
            statusMessage = "Conversion finished."
            conversionProgress = 1
        } catch {
            if (error as? VideoConversionServiceError) == .cancelled {
                statusMessage = "Conversion cancelled."
            } else {
                statusMessage = "Conversion failed."
                errorMessage = error.localizedDescription
            }

            do {
                workflowState = try planner.transition(from: workflowState, event: .conversionFailed)
                applyWorkflowState()
            } catch {
                workflowStep = .convert
            }
        }

        isConverting = false
        isCancellingConversion = false
    }

    func cancelConversion() {
        guard canCancelConversion else { return }
        isCancellingConversion = true
        statusMessage = "Cancelling..."
        conversionService.cancelCurrentConversion()
    }

    func saveResultToPhotoLibrary() async -> String {
        guard let convertedVideoURL else {
            return "No converted video to save."
        }

        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            return "Photo Library permission is required to save the converted video."
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: convertedVideoURL)
            }
            return "Saved to Photos."
        } catch {
            return "Save failed: \(error.localizedDescription)"
        }
    }

    func restartFlow() {
        do {
            workflowState = try planner.transition(from: workflowState, event: .restart)
            applyWorkflowState()
        } catch {
            workflowStep = .source
        }

        pickerItem = nil
        sourceMetadata = nil
        sourcePreviewImage = nil
        capabilities = []
        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        errorMessage = nil
        validationMessage = nil
        statusMessage = "Pick a video from Photos or Files to begin."
        isLoadingSourceDetails = false
        isConverting = false
        isCancellingConversion = false
        conversionProgress = nil
    }

    private func loadSource(from sourceURL: URL) async throws {
        let metadata = try await metadataInspector.inspect(url: sourceURL)
        let capabilities = metadataInspector.exportCapabilities(for: sourceURL)
        guard !capabilities.isEmpty else {
            throw ConversionModelError.noExportCapability
        }

        let preview = await metadataInspector.generateFirstFramePreview(from: sourceURL, maxDimension: 1_024)

        sourceMetadata = metadata
        self.capabilities = capabilities
        sourcePreviewImage = preview

        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        conversionProgress = nil

        normalizeClipRange()
        ensureSelectedPresetIsSupported()
        ensureSelectedFileTypeIsSupported()
        validateCurrentPlan()

        workflowState = try planner.transition(from: workflowState, event: .sourceSelected)
        applyWorkflowState()

        isLoadingSourceDetails = false
        statusMessage = "Video loaded. Configure output and convert."
    }

    private func restoreSettings() {
        isRestoringDraftSettings = true

        let draft = settingsStore.loadDraftSettings()
        selectedPresetID = draft.preferredPresetName ?? OutputPresetOption.autoID
        selectedFileTypeID = draft.preferredFileTypeIdentifier ?? OutputFileTypeOption.autoID
        optimizeForNetworkUse = draft.optimizeForNetworkUse
        clipStartSeconds = draft.clipStartSeconds
        if let clipEnd = draft.clipEndSeconds {
            useClipEnd = true
            clipEndSeconds = clipEnd
        } else {
            useClipEnd = false
            clipEndSeconds = 0
        }

        isRestoringDraftSettings = false
        validateCurrentPlan()
    }

    private func applyShowcaseStateIfNeeded() {
        guard let showcaseStep = ProcessInfo.processInfo.environment["SHOWCASE_STEP"] else {
            return
        }

        let mockMetadata = VideoMetadata(
            sourceURL: FileManager.default.temporaryDirectory.appendingPathComponent("showcase-source.mov"),
            durationSeconds: 18.4,
            fileSizeBytes: 24_800_000,
            width: 1920,
            height: 1080,
            frameRate: 30,
            sourceContainerIdentifier: ConversionContainer.mov.identifier,
            preferredTransform: .identity
        )

        sourceMetadata = mockMetadata
        sourcePreviewImage = UIImage(systemName: "film.fill")
        capabilities = [
            ConversionPresetCapability(
                presetName: AVAssetExportPresetHighestQuality,
                fileTypeIdentifiers: [
                    ConversionContainer.mp4.identifier,
                    ConversionContainer.mov.identifier
                ]
            ),
            ConversionPresetCapability(
                presetName: AVAssetExportPresetMediumQuality,
                fileTypeIdentifiers: [
                    ConversionContainer.mp4.identifier,
                    ConversionContainer.m4v.identifier
                ]
            )
        ]

        ensureSelectedPresetIsSupported()
        ensureSelectedFileTypeIsSupported()
        normalizeClipRange()
        validateCurrentPlan()

        switch showcaseStep {
        case "source":
            workflowState = ConversionWorkflowState(step: .source, isConverting: false)
            sourceMetadata = nil
            sourcePreviewImage = nil
            capabilities = []
            statusMessage = "Pick a video from Photos or Files to begin."
        case "convert":
            workflowState = ConversionWorkflowState(step: .convert, isConverting: false)
            statusMessage = "Video loaded. Configure output and convert."
        case "result":
            workflowState = ConversionWorkflowState(step: .result, isConverting: false)
            statusMessage = "Conversion finished."
            convertedFileSizeBytes = 9_300_000
            convertedVideoURL = nil
        default:
            break
        }

        applyWorkflowState()
    }

    private func currentSettings() -> VideoConversionSettings {
        VideoConversionSettings(
            preferredPresetName: selectedPresetID == OutputPresetOption.autoID ? nil : selectedPresetID,
            preferredFileTypeIdentifier: selectedFileTypeID == OutputFileTypeOption.autoID ? nil : selectedFileTypeID,
            optimizeForNetworkUse: optimizeForNetworkUse,
            clipStartSeconds: clipStartSeconds,
            clipEndSeconds: useClipEnd ? clipEndSeconds : nil
        )
    }

    private func currentPlan() throws -> ConversionPlan {
        guard let sourceMetadata else {
            throw ConversionPlannerError.noPresetCapabilities
        }

        return try planner.resolvePlan(
            sourceDurationSeconds: sourceMetadata.durationSeconds,
            sourceContainerIdentifier: sourceMetadata.sourceContainerIdentifier,
            capabilities: capabilities,
            settings: currentSettings()
        )
    }

    private func normalizeClipRange() {
        guard let sourceDuration = sourceMetadata?.durationSeconds else { return }

        let clampedStart = min(max(0, clipStartSeconds), sourceDuration)
        if clampedStart != clipStartSeconds {
            clipStartSeconds = clampedStart
            return
        }

        if !useClipEnd {
            if clipEndSeconds != sourceDuration {
                clipEndSeconds = sourceDuration
            }
            return
        }

        let minimumEnd = min(sourceDuration, clampedStart + 0.1)
        let clampedEnd = min(max(minimumEnd, clipEndSeconds), sourceDuration)
        if clampedEnd != clipEndSeconds {
            clipEndSeconds = clampedEnd
        }
    }

    private func ensureSelectedPresetIsSupported() {
        guard selectedPresetID != OutputPresetOption.autoID else { return }
        if !capabilities.contains(where: { $0.presetName == selectedPresetID }) {
            selectedPresetID = OutputPresetOption.autoID
        }
    }

    private func ensureSelectedFileTypeIsSupported() {
        guard selectedFileTypeID != OutputFileTypeOption.autoID else { return }

        let supportedIdentifiers: [String]
        if selectedPresetID == OutputPresetOption.autoID {
            supportedIdentifiers = planner.allOutputFileTypeIdentifiers(capabilities: capabilities)
        } else {
            supportedIdentifiers = capabilities.first(where: { $0.presetName == selectedPresetID })?.fileTypeIdentifiers ?? []
        }

        if !supportedIdentifiers.contains(selectedFileTypeID) {
            selectedFileTypeID = OutputFileTypeOption.autoID
        }
    }

    private func validateCurrentPlan() {
        guard sourceMetadata != nil else {
            validationMessage = nil
            return
        }

        do {
            _ = try currentPlan()
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func persistSettingsIfNeeded() {
        guard !isRestoringDraftSettings else { return }
        settingsStore.saveDraftSettings(currentSettings())
    }

    private func presetTitle(_ presetName: String) -> String {
        capabilities.first(where: { $0.presetName == presetName })?.shortTitle ?? presetName
    }

    private func applyWorkflowState() {
        workflowStep = workflowState.step
    }

    private func copyImportedVideoToTemporaryLocation(from url: URL) throws -> URL {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let filename = "imported-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
