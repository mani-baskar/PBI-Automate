# V1 Development Status

Branch: `dev/v1-smart-layout`

`main` is intentionally untouched until V1 passes real Power BI Desktop verification.

## Implemented

- [x] Portable Windows PowerShell 5.1 launcher
- [x] WinForms desktop UI
- [x] PBIP / project folder / .Report folder discovery
- [x] PBIP artifacts[].report.path resolution when multiple report folders exist
- [x] Enhanced PBIR validation
- [x] Page discovery and display names
- [x] Visual geometry reader
- [x] Automatic rough row/column clustering
- [x] Wide/tall span inference
- [x] Smart aligned grid proposal
- [x] Default 5-unit outer margin
- [x] Default 5-unit gap
- [x] Before/after schematic preview
- [x] Bounds and overlap validation
- [x] Source-file hash protection after Analyze
- [x] Backup before write
- [x] Geometry-only text update for x/y/width/height
- [x] Encoding/BOM preservation
- [x] Temporary-file validation
- [x] Post-write geometry verification
- [x] Automatic rollback on write failure
- [x] Undo latest apply
- [x] Local operation logging
- [x] Dependency-free automated integration test
- [x] GitHub Actions test on Windows PowerShell 5.1
- [x] MIT license
- [x] Manual Power BI test checklist

## Automated verification

GitHub Actions workflow:

`V1 Windows PowerShell Tests`

Latest expanded test coverage includes:

- PowerShell syntax parsing for all source files
- core/UI module import
- WinForms preview control creation
- Full WinForms window construction
- default configuration
- PBIP discovery
- page reading
- visual reading
- row/column detection
- wide visual span detection
- deterministic layout generation
- bounds/overlap validation
- stale PBIR source detection
- backup creation
- geometry write
- preservation of non-geometry payload
- written-coordinate verification
- automatic rollback after failed writes
- post-apply hash protection before Undo
- byte-for-byte Undo restore
- temporary-file cleanup

Current expanded suite result: **52 assertions passed on Windows PowerShell 5.1**.

## Release blockers

V1 is **not yet release-ready**. These are still required:

- [ ] Run the automated test once more on the final V1 commit.
- [ ] Test the WinForms application interactively on a normal Windows desktop.
- [ ] Test against at least one real enhanced-PBIR Power BI project.
- [ ] Confirm Git diff contains only intended geometry changes.
- [ ] Reload/open the modified PBIP in Power BI Desktop.
- [ ] Confirm DAX, fields, filters, visuals, and interactions remain intact.
- [ ] Verify Undo using the real test report.
- [ ] Fix any real-report layout edge cases discovered.
- [ ] Final documentation/release cleanup.
- [ ] Merge to main only after all release blockers pass.

See `docs/V1-Test-Checklist.md` for the manual procedure.
