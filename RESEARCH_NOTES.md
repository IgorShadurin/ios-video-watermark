# Research Notes (2026-02-24)

## What users commonly want
- Fast, simple conversion flow with broad format options and quality controls.
- Clear presets for common use cases plus optional advanced controls.
- Local/private processing options (or at least transparent handling).
- Progress visibility, cancellation, and reliable output file handling.

## Source summary
1. App Store listing (`The Video Converter`) emphasizes many input formats, output flexibility, cloud/local sources, and quick conversion UX.
   - https://apps.apple.com/us/app/the-video-converter/id893347665
2. HandBrake official features emphasize broad input support, device presets, batch queue, and quality-focused conversion controls.
   - https://handbrake.fr/features.php
3. Apple AVFoundation docs and AVAssetExportSession guidance emphasize dynamic capability checks (preset compatibility + supported file types) rather than hardcoded assumptions.
   - https://developer.apple.com/documentation/avfoundation/avassetexportsession
   - https://developer.apple.com/documentation/avfoundation/avassetexportsession/exportpresets(compatiblewith:)
   - https://developer.apple.com/documentation/avfoundation/avassetexportsession/supportedfiletypes
   - https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html

## Product decisions applied in this implementation
- Keep primary UX minimal: Source -> Convert -> Result.
- Hide advanced controls by default, but expose full conversion controls when expanded.
- Determine supported preset/file types dynamically per selected source video.
- Provide cancellation for conversion and robust cleanup on cancel/failure.
- Keep processing local on-device via AVFoundation.
