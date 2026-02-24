# Test Strategy

- Unit tests for watermark layout sizing/positioning using a dedicated planner in `CompressionPlanner`.
- Unit tests for workflow transition guardrails.
- Manual simulator checks should verify:
  - Import via Photos + Files with multiple files.
  - Watermark image selection, slider updates (size, opacity, position).
  - Batch execution across at least 3 videos.
  - Cancel action aborts active export and clears partial output.
  - Save/Share actions from result rows.
