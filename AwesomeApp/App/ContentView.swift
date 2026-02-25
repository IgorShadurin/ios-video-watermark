import AVKit
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VideoConversionViewModel()
    @State private var isVideoFileImporterPresented = false
    @State private var saveMessage: String?
    @State private var animateCards = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
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
                    .padding(.bottom, 20)
                    .onAppear { animateCards = true }
                    .onChange(of: viewModel.workflowStep) { _, _ in
                        withAnimation(.snappy(duration: 0.35)) {
                            animateCards = false
                        }
                        withAnimation(.snappy(duration: 0.35).delay(0.05)) {
                            animateCards = true
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.99, blue: 1.00),
                    Color(red: 0.93, green: 0.95, blue: 0.99),
                    Color(red: 0.99, green: 0.97, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.24), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 280
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: -110, y: -160)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.mint.opacity(0.2), .clear],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: 180, y: 280)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Watermark Studio")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.24, blue: 0.45), Color(red: 0.17, green: 0.42, blue: 0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Create branded batches in one pass")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                )
        )
        .offset(y: animateCards ? 0 : -12)
        .opacity(animateCards ? 1 : 0.2)
        .animation(.easeOut(duration: 0.4), value: animateCards)
    }

    private var stepRail: some View {
        HStack(spacing: 10) {
            stepChip(title: "Source", icon: "tray.and.arrow.down", index: "01", isActive: viewModel.workflowStep == .source)
            stepChip(title: "Settings", icon: "slider.horizontal.3", index: "02", isActive: viewModel.workflowStep == .convert)
            stepChip(title: "Results", icon: "checkmark.circle", index: "03", isActive: viewModel.workflowStep == .result)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private func stepChip(title: String, icon: String, index: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.blue.opacity(0.2) : Color.white.opacity(0.55))
                        .frame(width: 18, height: 18)
                    Text(index)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(isActive ? .blue : .secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
            }

            HStack(spacing: 6) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .tracking(0.2)
            }
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isActive
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Color.white.opacity(0.74))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue.opacity(0.4) : Color.blue.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: isActive ? Color.blue.opacity(0.15) : .clear, radius: 14, x: 0, y: 8)
    }

    private var sourceStep: some View {
        VStack(spacing: 16) {
            heroSection(
                title: "Import Media",
                icon: "play.rectangle.on.rectangle",
                subtitle: "Drag in clips from Photos or Files and let the queue build automatically."
            )

            statusCard(title: "Session", body: viewModel.statusMessage, status: viewModel.errorMessage)

            card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Add source videos")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Spacer(minLength: 0)
                        Text("\(viewModel.queuedVideos.count)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.16))
                            )
                            .foregroundStyle(.blue)
                    }

                    PhotosPicker(
                        selection: $viewModel.videoPickerItems,
                        maxSelectionCount: 25,
                        matching: .videos
                    ) {
                        actionButton("Pick from Photos", icon: "photo.stack", primary: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isVideoFileImporterPresented = true
                    } label: {
                        actionButton("Pick from Files", icon: "folder", primary: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isLoadingSourceDetails {
                glassSurface {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading selected media...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.queuedVideos.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Queued Videos")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(viewModel.queuedVideos.enumerated()), id: \.element.id) { index, queued in
                            HStack(spacing: 12) {
                                thumbnail(queued.previewImage)
                                    .frame(width: 66, height: 66)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(queued.name)
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                        .lineLimit(1)
                                    Text(queued.title)
                                        .font(.system(.footnote, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(queued.sizeText)
                                        .font(.system(.caption, design: .rounded, weight: .semibold))
                                        .foregroundStyle(.blue)
                                }

                                Spacer(minLength: 0)

                                Text(String(format: "#%d", index + 1))
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Capsule().fill(Color.white.opacity(0.46)))

                                Button(role: .destructive) {
                                    withAnimation(.spring()) {
                                        viewModel.removeQueuedVideo(queued.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
    }

    private var convertStep: some View {
        VStack(spacing: 16) {
            heroSection(
                title: "Watermark Controls",
                icon: "wand.and.stars",
                subtitle: "Fine tune the look, position, and transparency before running a batch."
            )
            convertWatermarkCard
            convertSettingsCard
            convertProgressAction

            if viewModel.canStartProcess {
                Button {
                    Task { await viewModel.startProcessing() }
                } label: {
                    Label("Apply to All Videos", systemImage: "wand.and.sparkles")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .scaleEffect(viewModel.canStartProcess ? 1 : 0.98)
                .shadow(color: Color.blue.opacity(0.35), radius: 14, x: 0, y: 8)
            }

            if viewModel.isConverting {
                convertProgressCard
            }

            statusCard(title: "Status", body: viewModel.statusMessage, status: viewModel.errorMessage)
        }
    }

    private var convertWatermarkCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Watermark")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 84, height: 84)

                        if let image = viewModel.watermarkImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.watermarkImage == nil {
                            Text("No watermark selected")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text("Choose one image to continue")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Watermark loaded")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text("Size: \(viewModel.sizeText)  •  Opacity: \(viewModel.opacityText)")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                PhotosPicker(selection: $viewModel.watermarkPickerItem, matching: .images) {
                    Label("Change Watermark", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.12)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var convertSettingsCard: some View {
        card { ConvertSettingsCardContent(viewModel: viewModel) }
    }

    private var convertProgressAction: some View {
        Group {
            if viewModel.canStartProcess {
                Button {
                    Task { await viewModel.startProcessing() }
                } label: {
                    Label("Apply to All Videos", systemImage: "wand.and.sparkles")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .shadow(color: Color.blue.opacity(0.35), radius: 14, x: 0, y: 8)
            } else {
                EmptyView()
            }
        }
    }

    private var convertProgressCard: some View {
        glassSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Watermarking")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(viewModel.conversionProgressText)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.blue)
                }

                ProgressView(value: viewModel.conversionProgress ?? 0)
                    .tint(.blue)

                Text(viewModel.statusMessage)
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

    private var resultStep: some View {
        VStack(spacing: 16) {
            heroSection(
                title: "Batch Completed",
                icon: "sparkles.rectangle.stack",
                subtitle: "Your stamped videos are ready to save or share."
            )

            statusCard(title: "Session", body: viewModel.statusMessage, status: viewModel.errorMessage)

            if !viewModel.results.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Results")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Spacer(minLength: 0)
                            Text("\(viewModel.results.count)")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }

                        ForEach(viewModel.results) { result in
                            VStack(spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.sourceName)
                                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                                            .lineLimit(1)
                                        Text("Output: \(humanReadableSize(result.outputSizeBytes))")
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    Text("✓")
                                        .font(.system(.title3, design: .rounded, weight: .black))
                                        .foregroundStyle(.green)
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
                            .padding(.vertical, 6)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Color.white.opacity(0.4)),
                                alignment: .bottom
                            )
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                viewModel.restartFlow()
            } label: {
                actionButton("Create New Watermark Job", icon: "arrow.uturn.left", primary: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
            )
            .shadow(color: Color.blue.opacity(0.15), radius: 20, x: 0, y: 12)
            .offset(y: animateCards ? 0 : 12)
            .opacity(animateCards ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: animateCards)
    }

    private func glassSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
    }

    private func heroSection(title: String, icon: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.25), Color.mint.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.8), Color.blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
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

    private func thumbnail(_ image: UIImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.52))
                .frame(width: 66, height: 66)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
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
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                          )
                        : AnyShapeStyle(Color.white.opacity(0.7))
                    )
            )
            .overlay(
                primary
                ? RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                : RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1)
            )
    }
}

private struct ConvertSettingsCardContent: View {
    @ObservedObject var viewModel: VideoConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading
            scaleRow
            opacityRow
            horizontalOffsetRow
            verticalOffsetRow
            quickPositionTitle
            quickPositionButtons
            validation
        }
    }

    private var sectionHeading: some View {
        Text("Placement and look")
            .font(.system(.headline, design: .rounded, weight: .bold))
    }

    private var scaleRow: some View {
        settingRow(
            title: "Scale",
            valueText: viewModel.sizeText,
            icon: "sparkles",
            value: Binding(
                get: { viewModel.watermarkSettings.sizePercent },
                set: { viewModel.updateSize($0) }
            ),
            range: 6...60
        )
    }

    private var opacityRow: some View {
        settingRow(
            title: "Opacity",
            valueText: viewModel.opacityText,
            icon: "eye",
            value: Binding(
                get: { viewModel.watermarkSettings.opacity },
                set: { viewModel.updateOpacity($0) }
            ),
            range: 0.05...1
        )
    }

    private var horizontalOffsetRow: some View {
        settingRow(
            title: "Horizontal Offset",
            valueText: "\(Int(viewModel.watermarkSettings.positionXPercent))%",
            icon: "arrow.left.and.right",
            value: Binding(
                get: { viewModel.watermarkSettings.positionXPercent },
                set: { viewModel.updateX($0) }
            ),
            range: 0...100
        )
    }

    private var verticalOffsetRow: some View {
        settingRow(
            title: "Vertical Offset",
            valueText: "\(Int(viewModel.watermarkSettings.positionYPercent))%",
            icon: "arrow.up.and.down",
            value: Binding(
                get: { viewModel.watermarkSettings.positionYPercent },
                set: { viewModel.updateY($0) }
            ),
            range: 0...100
        )
    }

    private var quickPositionTitle: some View {
        Text("Quick positions")
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .padding(.top, 2)
    }

    private var quickPositionButtons: some View {
        VStack(spacing: 10) {
            quickPositionRow(first: 0, second: 1, third: 2)
            quickPositionRow(first: 3, second: 4, third: 5)
            quickPositionRow(first: 6, second: 7, third: 8)
            quickPositionRow(first: 9, second: nil, third: nil)
        }
    }

    private func quickPositionRow(first: Int, second: Int?, third: Int?) -> some View {
        HStack(spacing: 10) {
            quickPositionButton(viewModel.positionPresets[first])

            if let second {
                quickPositionButton(viewModel.positionPresets[second])
            }

            if let third {
                quickPositionButton(viewModel.positionPresets[third])
            }

            Spacer(minLength: 0)
        }
    }

    private func quickPositionButton(_ preset: WatermarkPositionPreset) -> some View {
        Button {
            viewModel.applyPreset(preset)
        } label: {
            Text(preset.label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        viewModel.selectedPreset == preset
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.25), Color.cyan.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                          )
                        : AnyShapeStyle(Color.white.opacity(0.65))
                    )
            )
                .foregroundStyle(viewModel.selectedPreset == preset ? .blue : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.selectedPreset == preset ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
                )
        }
    }

    private var validation: some View {
        Group {
            if let validation = viewModel.validationMessage {
                Text(validation)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func settingRow(
        title: String,
        valueText: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text(title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(valueText)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.blue)
            }

            Slider(value: value, in: range)
        }
    }
}
