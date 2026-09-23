# PBI Automate — V1 Architecture

V1 is a portable Windows PowerShell 5.1 + WinForms utility for PBIP/PBIR report layout automation.

## Layering

- UI: WinForms only. No report mutation logic in event handlers.
- ProjectDiscovery: resolves .pbip/project/.Report paths.
- PBIRReader: reads pages and supported visual geometry.
- LayoutAnalyzer: detects rough row/column tracks and visual spans.
- SmartLayoutEngine: produces deterministic target geometry using configured margin/gap.
- LayoutValidator: checks bounds, geometry, collisions and expected visual count.
- BackupService: creates operation backups outside the PBIP project.
- PBIRWriter: writes only x/y/width/height, then re-reads and verifies.
- UndoService: restores the most recent successful operation.
- Logging: writes user-local operation logs.

## V1 safety boundary

V1 must never modify TMDL, DAX, relationships, queries, filters, visual bindings, report theme, bookmarks, mobile layouts, or unrelated visual formatting.

## Current development branch

dev/v1-smart-layout

main remains untouched until V1 is manually verified and ready for public release.
