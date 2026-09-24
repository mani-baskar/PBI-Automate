# Changelog

All notable changes to PBI Automate will be documented here.

## [Unreleased] - V1 Smart Layout

### Added

- Portable Windows PowerShell 5.1 + WinForms application.
- PBIP, project-folder, and .Report-folder selection.
- PBIP `artifacts[].report.path` resolution.
- Enhanced PBIR page and visual discovery.
- Smart row/column analysis with automatic tolerance.
- Wide/tall visual span inference.
- Deterministic 5-unit margin and 5-unit gap layout proposal.
- Before/after schematic preview.
- Bounds and overlap validation.
- Source hash protection against stale Analyze results.
- Backups stored outside the PBIP project.
- Geometry-only visual.json edits.
- Encoding/BOM preservation.
- Temporary JSON validation and post-write verification.
- Automatic rollback after a failed write.
- Post-apply hash protection for Undo.
- Byte-for-byte Undo restoration.
- User-local activity logs.
- Dependency-free Windows PowerShell integration tests.
- GitHub Actions validation on Windows PowerShell 5.1.
- MIT license and V1 manual test checklist.

### Verification

Current automated suite: **52 assertions passing on Windows PowerShell 5.1**.

### Pending before V1 release

- Interactive Windows desktop test.
- Real user PBIP/PBIR report test.
- Power BI Desktop reload/open verification.
- Final fixes from real-report testing.
- Merge to `main` only after the release checklist passes.
