import AVFoundation
import Combine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class VideoConversionViewModel: ObservableObject {
    private enum SourceLoadError: LocalizedError {
        case noImage
        case noVideo

        var errorDescription: String? {
            switch self {
            case .noImage:
                return "No watermark image was selected."
            case .noVideo:
                return "No source videos were selected."
            }
        }
    }

    @Published var videoPickerItems: [PhotosPickerItem] = []
    @Published var watermarkPickerItem: PhotosPickerItem?

    @Published private(set) var queuedVideos: [QueuedWatermarkVideo] = []
    @Published private(set) var watermarkSettings: WatermarkSettings = .defaultSettings {
        didSet {
            if isRestoringDefaults { return }
            persistSettings()
            persistWatermarkPositionDefaults()
            if watermarkSettings.positionPreset != .custom {
                let defaults = watermarkSettings.positionPreset.defaultPosition
                watermarkSettings.positionXPercent = defaults.0
                watermarkSettings.positionYPercent = defaults.1
            }
        }
    }
    @Published private(set) var selectedPreset: WatermarkPositionPreset = .bottomRight
    @Published private(set) var watermarkImage: UIImage?
    @Published private(set) var results: [WatermarkResult] = []
    @Published private(set) var sourcePreviewImage: UIImage?
    @Published private(set) var workflowStep: ConversionWorkflowStep = .source
    @Published private(set) var statusMessage = "Pick one or many videos and choose a watermark image."
    @Published private(set) var errorMessage: String?
    @Published private(set) var validationMessage: String?
    @Published private(set) var isLoadingSourceDetails = false
    @Published private(set) var isConverting = false
    @Published private(set) var isCancellingConversion = false
    @Published private(set) var conversionProgress: Double?
    @Published private(set) var conversionProgressText: String = "0%"

    private var workflowState = ConversionWorkflowState()
    private var isRestoringDefaults = true

    private let settingsStore = ConversionSettingsStore()
    private let metadataInspector = VideoMetadataInspector()
    private let conversionService = VideoConversionService()
    private let planner = WatermarkPlanner()

    let positionPresets = WatermarkPositionPreset.allCases

    init() {
        restoreSettings()
        isRestoringDefaults = false
    }

    var hasSource: Bool {
        !queuedVideos.isEmpty
    }

    var canStartProcess: Bool {
        hasSource && watermarkImage != nil && !isLoadingSourceDetails && !isConverting
    }

    var canCancelProcess: Bool {
        isConverting && !isCancellingConversion
    }

    var canSaveAll: Bool {
        !results.isEmpty && !isConverting
    }

    var hasPlan: Bool {
        !queuedVideos.isEmpty && watermarkImage != nil
    }

    var sizeText: String {
        "\(Int(watermarkSettings.sizePercent))%"
    }

    var opacityText: String {
        "\(Int(watermarkSettings.opacity * 100))%"
    }

    var positionText: String {
        "X \(Int(watermarkSettings.positionXPercent))% • Y \(Int(watermarkSettings.positionYPercent))%"
    }

    func applyPreset(_ preset: WatermarkPositionPreset) {
        var updated = watermarkSettings
        updated = updated.appliedPreset(preset)
        watermarkSettings = updated
        selectedPreset = preset
        if preset == .custom {
            validationMessage = "Manual position control"
        } else {
            validationMessage = nil
        }
    }

    func updateSize(_ value: Double) {
        watermarkSettings.sizePercent = value
    }

    func updateOpacity(_ value: Double) {
        watermarkSettings.opacity = value
    }

    func updateX(_ value: Double) {
        selectedPreset = .custom
        watermarkSettings.positionXPercent = value
        watermarkSettings.positionPreset = .custom
        persistSettings()
    }

    func updateY(_ value: Double) {
        selectedPreset = .custom
        watermarkSettings.positionYPercent = value
        watermarkSettings.positionPreset = .custom
        persistSettings()
    }

    func handleVideoPickerChange() async {
        let selected = videoPickerItems
        videoPickerItems = []
        guard !selected.isEmpty else { return }

        isLoadingSourceDetails = true
        errorMessage = nil
        statusMessage = "Reading source metadata..."

        for item in selected {
            do {
                guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw SourceLoadError.noVideo
                }
                await loadSource(from: picked.url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if isLoadingSourceDetails {
            isLoadingSourceDetails = false
        }

        statusMessage = queuedVideos.isEmpty
            ? "Pick one or many videos and choose a watermark image."
            : "Ready. Configure watermark and run batch processing."
        transitionToConvertIfNeeded()
    }

    func handleImportedVideos(urls: [URL]) async {
        guard !urls.isEmpty else { return }

        isLoadingSourceDetails = true
        errorMessage = nil
        statusMessage = "Reading source metadata..."

        for url in urls {
            let localURL = try? copyImportedVideoToTemporaryLocation(from: url)
            if let sourceURL = localURL {
                await loadSource(from: sourceURL)
            }
        }

        isLoadingSourceDetails = false
        if queuedVideos.isEmpty {
            statusMessage = "Pick one or many videos and choose a watermark image."
        } else {
            statusMessage = "Ready. Configure watermark and run batch processing."
            transitionToConvertIfNeeded()
        }
    }

    func handleWatermarkPickerChange() async {
        do {
            guard let item = watermarkPickerItem else {
                watermarkImage = nil
                return
            }
            watermarkPickerItem = nil

            if let image = try await item.loadTransferable(type: Data.self).flatMap(UIImage.init(data:)) {
                watermarkImage = image
            } else {
                throw SourceLoadError.noImage
            }
            statusMessage = "Watermark set. Ready to process \(queuedVideos.count) video(s)."
            transitionToConvertIfNeeded()
            persistSettings()
        } catch {
            errorMessage = error.localizedDescription
            watermarkImage = nil
        }
    }

    func removeQueuedVideo(_ id: UUID) {
        queuedVideos.removeAll { $0.id == id }
        if queuedVideos.isEmpty {
            workflowStep = .source
            workflowState = .init()
            validationMessage = nil
            statusMessage = "Pick one or many videos and choose a watermark image."
        }
    }

    func startProcessing() async {
        guard canStartProcess else {
            errorMessage = SourceLoadError.noVideo.localizedDescription
            return
        }

        do {
            workflowState = try planner.transition(from: workflowState, event: .conversionStarted)
            workflowStep = workflowState.step
        } catch {
            errorMessage = "Unable to start processing."
            return
        }

        guard let watermarkImage else {
            errorMessage = SourceLoadError.noImage.localizedDescription
            isConverting = false
            return
        }

        isConverting = true
        isCancellingConversion = false
        conversionProgress = 0
        conversionProgressText = "0%"
        errorMessage = nil
        validationMessage = nil
        statusMessage = "Preparing batch watermarking..."

        let urls = queuedVideos.map { $0.source.sourceURL }

        do {
            let processed = try await conversionService.applyWatermarkBatch(
                sourceURLs: urls,
                watermarkImage: watermarkImage,
                settings: watermarkSettings,
                outputFileType: .mp4
            ) { [weak self] done, total, progress in
                guard let self else { return }
                Task { @MainActor in
                    self.conversionProgress = progress
                    self.conversionProgressText = "\(Int((progress * 100).rounded()))%"
                    self.statusMessage = "Processing \(done) / \(total)"
                }
            }

            results = try await buildResults(urls: processed)

            workflowState = try planner.transition(from: workflowState, event: .conversionSucceeded)
            workflowStep = workflowState.step
            statusMessage = "Batch completed for \(results.count) video(s)."
            conversionProgress = 1
            conversionProgressText = "100%"
        } catch {
            if error is VideoConversionService.VideoConversionServiceError {
                statusMessage = "Processing stopped."
            } else {
                statusMessage = "Processing failed."
                errorMessage = error.localizedDescription
            }

            do {
                workflowState = try planner.transition(from: workflowState, event: .conversionFailed)
                workflowStep = workflowState.step
            } catch {
                workflowStep = .convert
            }
            results = []
        }

        isConverting = false
        isCancellingConversion = false
    }

    func cancelProcessing() {
        guard canCancelProcess else { return }
        isCancellingConversion = true
        statusMessage = "Cancelling batch job..."
        conversionService.cancelCurrentConversion()
    }

    func saveResult(_ result: WatermarkResult) async -> String {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            return "Photo access is required to save watermarked videos."
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.outputURL)
            }
            return "Saved: \(result.sourceName)"
        } catch {
            return "Save failed: \(error.localizedDescription)"
        }
    }

    func saveAllResults() async -> [String] {
        var messages: [String] = []
        for result in results {
            messages.append(await saveResult(result))
        }
        return messages
    }

    func restartFlow() {
        workflowState = .init()
        workflowStep = .source
        watermarkImage = nil
        watermarkPickerItem = nil
        results = []
        errorMessage = nil
        validationMessage = nil
        conversionProgress = nil
        conversionProgressText = "0%"
        statusMessage = "Pick one or many videos and choose a watermark image."
    }

    private func buildResults(urls: [URL]) async throws -> [WatermarkResult] {
        var output: [WatermarkResult] = []
        output.reserveCapacity(urls.count)

        for (index, outputURL) in urls.enumerated() {
            let sourceName = queuedVideos[index].source.sourceURL.lastPathComponent
            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
            let size = Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)
            output.append(WatermarkResult(sourceName: sourceName, outputURL: outputURL, outputSizeBytes: size))
        }

        return output
    }

    private func loadSource(from sourceURL: URL) async {
        do {
            let metadata = try await metadataInspector.inspect(url: sourceURL)
            let preview = await metadataInspector.generateFirstFramePreview(from: sourceURL, maxDimension: 420)

            if !queuedVideos.contains(where: { $0.source.sourceURL == sourceURL }) {
                queuedVideos.append(QueuedWatermarkVideo(source: metadata, previewImage: preview))
            }

            sourcePreviewImage = preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyImportedVideoToTemporaryLocation(from url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func persistSettings() {
        settingsStore.saveSettings(watermarkSettings)
    }

    private func restoreSettings() {
        watermarkSettings = settingsStore.loadSettings()
        selectedPreset = watermarkSettings.positionPreset
    }

    private func persistWatermarkPositionDefaults() {
        statusMessage = hasSource
            ? "Ready. Configure watermark and run batch processing."
            : "Pick one or many videos and choose a watermark image."
    }

    private func transitionToConvertIfNeeded() {
        guard !queuedVideos.isEmpty && watermarkImage != nil else { return }

        do {
            workflowState = try planner.transition(from: workflowState, event: .sourceSelected)
            workflowStep = workflowState.step
        } catch {
            workflowStep = .convert
        }
    }
}

final class WatermarkPlanner {
    func transition(from state: ConversionWorkflowState, event: ConversionWorkflowEvent) throws -> ConversionWorkflowState {
        switch event {
        case .sourceSelected:
            return ConversionWorkflowState(step: .convert, isConverting: false)
        case .sourceCleared:
            return ConversionWorkflowState(step: .source, isConverting: false)
        case .conversionStarted:
            guard state.step == .convert || state.step == .source else { throw ConversionWorkflowError.invalidTransition }
            return ConversionWorkflowState(step: .convert, isConverting: true)
        case .conversionSucceeded:
            guard state.isConverting else { throw ConversionWorkflowError.invalidTransition }
            return ConversionWorkflowState(step: .result, isConverting: false)
        case .conversionFailed:
            guard state.isConverting else { throw ConversionWorkflowError.invalidTransition }
            return ConversionWorkflowState(step: .convert, isConverting: false)
        case .restart:
            return ConversionWorkflowState(step: .source, isConverting: false)
        }
    }
}
