import AVKit
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VideoConversionViewModel()
    @State private var isVideoFileImporterPresented = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 12) {
                    header
                    stepRail

                    Group {
                        switch viewModel.workflowStep {
                        case .source:
                            sourceStep
                        case .convert:
                            convertStep
                        case .result:
                            resultStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .navigationBarHidden(true)
        }
        .onChange(of: viewModel.videoPickerItems) { _, _ in
            Task { await viewModel.handleVideoPickerChange() }
        }
        .onChange(of: viewModel.watermarkPickerItem) { _, _ in
            Task { await viewModel.handleWatermarkPickerChange() }
        }
        .fileImporter(
            isPresented: $isVideoFileImporterPresented,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.handleImportedVideos(urls: urls) }
            case .failure(let error):
                saveMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert("Video Watermark", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.99, blue: 1.00),
                Color(red: 0.94, green: 0.96, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Watermark")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Batch watermarking with dynamic size and transparency")
                    .font(.system(.subheadline, design: .rounded, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
        }
    }

    private var stepRail: some View {
        HStack(spacing: 8) {
            stepChip(title: "Source", icon: "tray.and.arrow.down", isActive: viewModel.workflowStep == .source)
            stepChip(title: "Settings", icon: "slider.horizontal.3", isActive: viewModel.workflowStep == .convert)
            stepChip(title: "Results", icon: "checkmark.circle", isActive: viewModel.workflowStep == .result)
        }
    }

    private func stepChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(isActive ? .white : .primary.opacity(0.7))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? AnyShapeStyle(LinearGradient(colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.85)], startPoint: .leading, endPoint: .trailing) ) : AnyShapeStyle(Color.white.opacity(0.8)))
        )
    }

    private var sourceStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                statusCard(title: "Import", body: viewModel.statusMessage, status: viewModel.errorMessage)

                PhotosPicker(
                    selection: $viewModel.videoPickerItems,
                    maxSelectionCount: 25,
                    matching: .videos
                ) {
                    actionButton("Pick Videos", icon: "photo.stack", primary: true)
                }
                .buttonStyle(.plain)

                Button {
                    isVideoFileImporterPresented = true
                } label: {
                    actionButton("Pick from Files", icon: "folder", primary: false)
                }
                .buttonStyle(.plain)

                if viewModel.isLoadingSourceDetails {
                    ProgressView("Loading selected media...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.queuedVideos.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Queued Videos")
                                .font(.system(.headline, design: .rounded))
                            ForEach(viewModel.queuedVideos) { queued in
                                HStack(spacing: 10) {
                                    Group {
                                        if let image = queued.previewImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white.opacity(0.6))
                                                .overlay { Image(systemName: "video.fill") }
                                        }
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(queued.name)
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                            .lineLimit(1)
                                        Text(queued.title)
                                            .font(.system(.footnote, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Text(queued.sizeText)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    Button(role: .destructive) {
                                        withAnimation {
                                            viewModel.removeQueuedVideo(queued.id)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
        }
    }

    private var convertStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Watermark Image")
                            .font(.system(.headline, design: .rounded))

                        if let image = viewModel.watermarkImage {
                            HStack(spacing: 10) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                VStack(alignment: .leading) {
                                    Text("Selected")
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    Text("Size: \(viewModel.sizeText)  •  Opacity: \(viewModel.opacityText)")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                        }

                        PhotosPicker(selection: $viewModel.watermarkPickerItem, matching: .images) {
                            Label("Choose Watermark", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.75)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Adjust watermark")
                            .font(.system(.headline, design: .rounded))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Size \(viewModel.sizeText)")
                            Slider(value: Binding(
                                get: { viewModel.watermarkSettings.sizePercent },
                                set: { viewModel.updateSize($0) }
                            ), in: 6...60)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Opacity \(viewModel.opacityText)")
                            Slider(value: Binding(
                                get: { viewModel.watermarkSettings.opacity },
                                set: { viewModel.updateOpacity($0) }
                            ), in: 0.05...1)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Horizontal \(Int(viewModel.watermarkSettings.positionXPercent))%")
                            Slider(value: Binding(
                                get: { viewModel.watermarkSettings.positionXPercent },
                                set: { viewModel.updateX($0) }
                            ), in: 0...100)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vertical \(Int(viewModel.watermarkSettings.positionYPercent))%")
                            Slider(value: Binding(
                                get: { viewModel.watermarkSettings.positionYPercent },
                                set: { viewModel.updateY($0) }
                            ), in: 0...100)
                        }

                        Text("Quick position")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .padding(.top, 4)

                        let columns = Array(repeating: GridItem(.flexible(minimum: 72)), count: 2)
                        LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(viewModel.positionPresets, id: \.self) { preset in
                                Button {
                                    viewModel.applyPreset(preset)
                                } label: {
                                    Text(preset.label)
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(viewModel.selectedPreset == preset
                                                      ? Color.blue.opacity(0.85)
                                                      : Color.white.opacity(0.8)
                                                )
                                        )
                                        .foregroundStyle(viewModel.selectedPreset == preset ? .white : .primary)
                                }
                            }
                        }

                        if let validation = viewModel.validationMessage {
                            Text(validation)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if viewModel.canStartProcess {
                    Button {
                        Task { await viewModel.startProcessing() }
                    } label: {
                        Label("Apply to All Videos", systemImage: "wand.and.sparkles")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isConverting {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: viewModel.conversionProgress ?? 0)
                            Text("\(viewModel.conversionProgressText) • \(viewModel.statusMessage)")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)

                            Button(role: .destructive) {
                                viewModel.cancelProcessing()
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.canCancelProcess)
                        }
                    }
                }

                statusCard(title: "Status", body: viewModel.statusMessage, status: viewModel.errorMessage)
            }
        }
    }

    private var resultStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                statusCard(title: "Batch Completed", body: viewModel.statusMessage, status: viewModel.errorMessage)

                if !viewModel.results.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(viewModel.results.count) videos saved")
                                .font(.system(.headline, design: .rounded, weight: .bold))

                            ForEach(viewModel.results) { result in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(result.sourceName)
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                            .lineLimit(1)

                                        Spacer(minLength: 0)

                                        Text(humanReadableSize(result.outputSizeBytes))
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 8) {
                                        ShareLink(item: result.outputURL) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                                .frame(maxWidth: .infinity)
                                        }

                                        Button {
                                            Task {
                                                let message = await viewModel.saveResult(result)
                                                saveMessage = message
                                            }
                                        } label: {
                                            Label("Save", systemImage: "square.and.arrow.down")
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            let messages = await viewModel.saveAllResults()
                            if let first = messages.first(where: { !$0.hasPrefix("Saved") }) {
                                saveMessage = first
                            } else {
                                saveMessage = "Save all completed."
                            }
                        }
                    } label: {
                        Label("Save All", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    viewModel.restartFlow()
                } label: {
                    actionButton("Create New Watermark Job", icon: "arrow.uturn.left", primary: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
            )
    }

    private func statusCard(title: String, body: String, status: String?) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(body)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                if let status {
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionButton(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(primary ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(primary
                      ? AnyShapeStyle(LinearGradient(colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(Color.white.opacity(0.7))
                )
        )
    }
}
