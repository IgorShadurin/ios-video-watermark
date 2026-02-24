# Research Notes

- Reviewed AVFoundation guide for overlaying animations and watermark layers: `AVVideoComposition` + `AVVideoCompositionCoreAnimationTool` is the canonical approach for video frame overlays.
- Used transform-aware rendering flow where render size is derived from `preferredTransform` applied to source video track size.
- Referenced AVFoundation export session behavior for `supportedFileTypes` to pick `.mp4` then `.mov` fallback.
- Added safety checks for cancellation, timestamp/asset validity, and temporary output cleanup.
