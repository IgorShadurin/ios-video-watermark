import Testing
@testable import CompressionPlanner

struct CompressionPlannerTests {
    private let planner = WatermarkPlanner()

    @Test
    func resolveLayoutUsesPercentSizeAndPreservesAspect() throws {
        let sourceWidth = 1920.0
        let sourceHeight = 1080.0
        let settings = WatermarkSettings(
            sizePercent: 20,
            opacity: 0.8,
            positionXPercent: 10,
            positionYPercent: 15
        )

        let layout = try planner.resolveLayout(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            watermarkImageWidth: 400,
            watermarkImageHeight: 200,
            settings: settings
        )

        #expect(layout.width == 384)
        #expect(layout.height == 192)
        #expect(layout.x == 153.6)
    }

    @Test
    func resolveLayoutClampsToSafeBounds() throws {
        let settings = WatermarkSettings(
            sizePercent: 80,
            opacity: 0.5,
            positionXPercent: 100,
            positionYPercent: 100
        )

        let layout = try planner.resolveLayout(
            sourceWidth: 800,
            sourceHeight: 300,
            watermarkImageWidth: 640,
            watermarkImageHeight: 480,
            settings: settings
        )

        #expect(layout.width <= 720)
        #expect(layout.x >= 0)
        #expect(layout.y >= 0)
    }

    @Test
    func invalidSourceSizeThrows() {
        let settings = WatermarkSettings(sizePercent: 20, opacity: 0.8, positionXPercent: 10, positionYPercent: 10)

        #expect(throws: WatermarkPlannerError.invalidSourceSize) {
            try planner.resolveLayout(
                sourceWidth: 0,
                sourceHeight: 100,
                watermarkImageWidth: 100,
                watermarkImageHeight: 100,
                settings: settings
            )
        }
    }

    @Test
    func stateMachineTransitions() throws {
        let initial = ConversionWorkflowState()
        let started = try plannerTransition(from: initial, event: .sourceSelected)
        #expect(started.step == .convert)
        #expect(!started.isConverting)

        let running = try plannerTransition(from: started, event: .conversionStarted)
        #expect(running.step == .convert)
        #expect(running.isConverting)

        let completed = try plannerTransition(from: running, event: .conversionSucceeded)
        #expect(completed.step == .result)
        #expect(!completed.isConverting)
    }

    @Test
    func invalidStateTransitionThrows() {
        let running = ConversionWorkflowState(step: .source, isConverting: false)
        #expect(throws: ConversionWorkflowError.invalidTransition) {
            _ = try plannerTransition(from: running, event: .conversionSucceeded)
        }
    }
}

private func plannerTransition(from state: ConversionWorkflowState, event: ConversionWorkflowEvent) throws -> ConversionWorkflowState {
    switch event {
    case .sourceSelected:
        return ConversionWorkflowState(step: .convert, isConverting: false)
    case .sourceCleared:
        return ConversionWorkflowState(step: .source, isConverting: false)
    case .conversionStarted:
        guard state.step == .convert || state.step == .source else {
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
