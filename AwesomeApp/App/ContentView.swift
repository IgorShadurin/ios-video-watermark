import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VideoConversionViewModel()
    @State private var isAdvancedSettingsExpanded = false
    @State private var isFileImporterPresented = false
    @State private var saveAlertMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                atmosphericBackground

                VStack(spacing: 10) {
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
                .padding(.top, 8)
            }
            .navigationBarHidden(true)
        }
        .onChange(of: viewModel.pickerItem) { _, _ in
            Task {
                await viewModel.handlePickerChange()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.handleImportedFile(url: url)
                }
            case .failure(let error):
                viewModel.handleImportFailure(error.localizedDescription)
            }
        }
        .alert(
            "Save Result",
            isPresented: Binding(
                get: { saveAlertMessage != nil },
                set: { if !$0 { saveAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveAlertMessage = nil
            }
        } message: {
            Text(saveAlertMessage ?? "")
                .font(uiFont(15, weight: .medium))
        }
    }

    private var atmosphericBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.93, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.00, green: 0.55, blue: 0.95).opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 24)
                .offset(x: 170, y: -250)

            Circle()
                .fill(Color(red: 1.00, green: 0.58, blue: 0.32).opacity(colorScheme == .dark ? 0.16 : 0.11))
                .frame(width: 240, height: 240)
                .blur(radius: 28)
                .offset(x: -170, y: 340)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Converter")
                    .font(uiFont(38, weight: .heavy))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Fast local conversion for your iPhone")
                    .font(uiFont(14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text("ON-DEVICE")
                    .font(uiFont(9, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
    }

    private var stepRail: some View {
        HStack(spacing: 8) {
            stepChip(title: "Source", icon: "tray.and.arrow.down", isActive: viewModel.workflowStep == .source)
            stepChip(title: "Convert", icon: "arrow.2.squarepath", isActive: viewModel.workflowStep == .convert)
            stepChip(title: "Result", icon: "checkmark.circle", isActive: viewModel.workflowStep == .result)
        }
    }

    private func stepChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(uiFont(13, weight: .semibold))
        }
        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
        )
    }

    private var sourceStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                glowCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Import Source")
                            .font(uiFont(26, weight: .bold))
                        Text("Any video your iPhone can decode")
                            .font(uiFont(14, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                        Text(viewModel.statusMessage)
                            .font(uiFont(13, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.55))
                    }
                }

                PhotosPicker(
                    selection: $viewModel.pickerItem,
                    matching: .videos,
                    preferredItemEncoding: .compatible,
                    photoLibrary: .shared()
                ) {
                    actionPill(title: "Pick from Photos", icon: "photo.on.rectangle", isPrimary: true)
                }
                .buttonStyle(.plain)

                Button {
                    isFileImporterPresented = true
                } label: {
                    actionPill(title: "Pick from Files", icon: "folder", isPrimary: false)
                }
                .buttonStyle(.plain)

                if viewModel.isLoadingSourceDetails {
                    glowCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading metadata...")
                                .font(uiFont(14, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.7))
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(uiFont(13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }

    private var convertStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                sourceCard

                glowCard {
                    VStack(alignment: .leading, spacing: 12) {
                        menuRow(
                            title: "Output Format",
                            systemImage: "doc",
                            selection: $viewModel.selectedFileTypeID,
                            options: viewModel.fileTypeOptions
                        )

                        menuRow(
                            title: "Quality Preset",
                            systemImage: "slider.horizontal.3",
                            selection: $viewModel.selectedPresetID,
                            options: viewModel.presetOptions
                        )

                        if let summary = viewModel.planSummaryText {
                            Text(summary)
                                .font(uiFont(12, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.55))
                        }
                    }
                }

                glowCard {
                    DisclosureGroup(isExpanded: $isAdvancedSettingsExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Optimize for network use", isOn: $viewModel.optimizeForNetworkUse)
                                .font(uiFont(14, weight: .medium))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clip start: \(formatSeconds(viewModel.clipStartSeconds))")
                                    .font(uiFont(13, weight: .semibold))
                                Slider(value: $viewModel.clipStartSeconds, in: viewModel.clipDurationRange)
                            }

                            Toggle("Trim end", isOn: $viewModel.useClipEnd)
                                .font(uiFont(14, weight: .medium))

                            if viewModel.useClipEnd {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Clip end: \(formatSeconds(viewModel.clipEndSeconds))")
                                        .font(uiFont(13, weight: .semibold))
                                    Slider(value: $viewModel.clipEndSeconds, in: viewModel.clipDurationRange)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Advanced Controls", systemImage: "slider.horizontal.3")
                            .font(uiFont(14, weight: .semibold))
                    }
                    .accentColor(Color.primary)
                }

                if let validation = viewModel.validationMessage {
                    Text(validation)
                        .font(uiFont(13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await viewModel.convert()
                    }
                } label: {
                    actionPill(title: "Convert Video", icon: "arrow.triangle.2.circlepath", isPrimary: true)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canConvert)

                if viewModel.isConverting {
                    glowCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: viewModel.conversionProgress ?? 0)
                            Text(viewModel.conversionProgressText ?? "Starting...")
                                .font(uiFont(12, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.65))

                            Button(role: .destructive) {
                                viewModel.cancelConversion()
                            } label: {
                                Label("Cancel conversion", systemImage: "xmark.circle")
                                    .font(uiFont(14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.canCancelConversion)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(uiFont(13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }

    private var resultStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                sourceCard

                glowCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Result")
                            .font(uiFont(24, weight: .bold))

                        if let outputSizeText = viewModel.outputSizeText {
                            Text("Output size: \(outputSizeText)")
                                .font(uiFont(15, weight: .semibold))
                        }

                        Text(viewModel.statusMessage)
                            .font(uiFont(13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }

                if let convertedVideoURL = viewModel.convertedVideoURL {
                    VideoPlayer(player: AVPlayer(url: convertedVideoURL))
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.55), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                saveAlertMessage = await viewModel.saveResultToPhotoLibrary()
                            }
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(uiFont(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSaveResult)

                        ShareLink(item: convertedVideoURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(uiFont(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    glowCard {
                        Text("Result preview appears after a full conversion run.")
                            .font(uiFont(13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.55))
                    }
                }

                Button {
                    viewModel.restartFlow()
                } label: {
                    actionPill(title: "Convert another video", icon: "plus", isPrimary: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }

    private var sourceCard: some View {
        glowCard {
            HStack(spacing: 10) {
                Group {
                    if let image = viewModel.sourcePreviewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                            .overlay {
                                Image(systemName: "video.fill")
                                    .foregroundStyle(Color.primary.opacity(0.5))
                            }
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Source")
                        .font(uiFont(18, weight: .bold))
                    if let sourceSummary = viewModel.sourceSummaryText {
                        Text(sourceSummary)
                            .font(uiFont(15, weight: .medium))
                    }
                    if let sourceSize = viewModel.sourceSizeText {
                        Text(sourceSize)
                            .font(uiFont(14, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.58))
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.49, blue: 0.97),
                Color(red: 0.00, green: 0.67, blue: 0.84)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func glowCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 12, y: 5)
    }

    private func actionPill(title: String, icon: String, isPrimary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(uiFont(20, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPrimary ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
    }

    private func menuRow(
        title: String,
        systemImage: String,
        selection: Binding<String>,
        options: [OutputFileTypeOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(uiFont(15, weight: .semibold))

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func menuRow(
        title: String,
        systemImage: String,
        selection: Binding<String>,
        options: [OutputPresetOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(uiFont(15, weight: .semibold))

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func uiFont(_ size: CGFloat, weight: Font.Weight) -> Font {
        let fontName: String
        switch weight {
        case .heavy, .black:
            fontName = "AvenirNext-Heavy"
        case .bold, .semibold:
            fontName = "AvenirNext-DemiBold"
        case .medium:
            fontName = "AvenirNext-Medium"
        default:
            fontName = "AvenirNext-Regular"
        }
        return .custom(fontName, size: size)
    }
}
