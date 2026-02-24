# PLAN

- [x] Confirm product scope from prompt and web research findings.
- [x] Define acceptance criteria and edge cases for iOS-native video conversion.
- [x] Implement/update core planner models for preset/file-type capability resolution (test-first).
- [x] Add unit tests for format resolution, validation, clip-range logic, and workflow state transitions.
- [x] Implement AVFoundation conversion service using `AVAssetExportSession` with cancellation safety and cleanup.
- [x] Implement source metadata + capability inspector for dynamic source-dependent support.
- [x] Build minimalist SwiftUI UX with hidden advanced settings by default.
- [x] Wire Photos + Files import flows and result export/save flow.
- [x] Persist user settings safely and restore on launch.
- [x] Run package tests and fix failures.
- [x] Build and launch on iPhone mini, regular iPhone, and Pro Max simulators.
- [x] Perform manual simulator validation to the maximum possible in this CLI flow and capture screenshots to `showcase/`.
- [x] Update README with features, QA outcomes, and showcase images.
- [x] Final cleanup and delivery report with exact file references.

## QA Notes
- Full click/tap UI automation (import -> convert -> save) is partially constrained in this terminal-only simulator workflow.
- App launch, layout fit, and light/dark visual checks were completed on target simulator classes.
