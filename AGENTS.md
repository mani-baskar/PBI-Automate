# AGENTS.md — PBI Automate

## Mission

Build **PBI Automate** as a real reusable Windows desktop utility for Power BI developers. It is not a demo or throwaway script.

The long-term product may automate multiple repetitive PBIP development tasks, but the current active release is **V1 Smart Layout only**. Do not invent or implement V2/V3 features until the user provides those requirements.

## Environment — non-negotiable

V1 must run on a locked-down Windows office machine with no additional software installation.

Use only:

- Windows PowerShell 5.1;
- built-in .NET Framework APIs;
- System.Windows.Forms;
- System.Drawing;
- native filesystem APIs;
- native PowerShell JSON parsing.

Do not require Python, Node.js, npm, .NET SDK, Visual Studio, NuGet, PowerShell Gallery modules, third-party EXEs, admin rights, internet access, Power BI/Fabric REST APIs, or execution-policy bypasses.

If corporate policy blocks unsigned scripts, document the need for approved signing/allow-listing. Never bypass security policy.

## Supported Power BI format

V1 targets Power BI Project + enhanced PBIR.

Expected structure:

```text
<Project>.pbip
<Project>.Report/
  definition.pbir
  definition/
    pages/
      pages.json
      <page-id>/
        page.json
        visuals/
          <visual-id>/
            visual.json
```

V1 may mutate only:

- position.x
- position.y
- position.width
- position.height

Do not modify DAX, TMDL, measures, relationships, queries, fields/bindings, filters, conditional formatting, bookmarks, mobile layout, themes, or unrelated report formatting.

Unsupported PBIR legacy input must fail safely with a clear message.

## Product rules

- Keep UI separate from core/business logic.
- Every mutation must be previewable.
- Every apply must create a backup first.
- Every write must be re-read and verified.
- Never silently modify a report.
- Fail safely and restore the backup on partial write failure.
- Preserve the user's existing layout intent; do not flatten every page into a naive grid.
- Large/wide/tall visuals must keep span intent.
- Do not leave temporary files inside the PBIP project.
- Logging and backups belong under the current user's local app-data folder.
- Keep PowerShell 5.1 compatibility.

## Git workflow

The public `main` branch must remain untouched during V1 development.

Active V1 branch:

```text
dev/v1-smart-layout
```

Make visible incremental commits on the development branch. Do not merge to main until:

1. automated V1 test passes on Windows PowerShell 5.1;
2. manual test checklist passes with at least one real enhanced-PBIR report;
3. Apply changes only intended geometry;
4. Undo restores the exact previous files;
5. Power BI Desktop opens/reloads the modified project successfully;
6. documentation is current.

After release, freeze/tag V1 before starting V2.

## V1 definition of done

A user must be able to:

1. launch the WinForms tool;
2. select a .pbip, project folder, or .Report folder;
3. discover the enhanced PBIR report;
4. list report pages;
5. select one page;
6. analyze supported visual containers;
7. detect rough rows/columns;
8. infer peer groups and visual spans;
9. generate a deterministic cleaned layout;
10. default to 5-unit outer margin and 5-unit gap;
11. correct obvious drift;
12. equalize peer visual geometry;
13. preserve large visual spans;
14. prevent overlaps;
15. keep visuals within the page;
16. preview before editing;
17. create a backup;
18. apply only x/y/width/height;
19. re-read and verify;
20. undo the latest apply;
21. produce readable logs;
22. close without temporary project files.

A V1 that merely moves a few rectangles is not complete.

## Architecture

Keep these modules independent:

- `ProjectDiscovery.psm1`: resolve PBIP/report paths.
- `PBIRReader.psm1`: read pages and visual geometry.
- `LayoutAnalyzer.psm1`: infer rows, columns, peers, and spans.
- `SmartLayoutEngine.psm1`: create proposed geometry.
- `LayoutValidator.psm1`: validate bounds and collisions.
- `BackupService.psm1`: create/restore operation backups.
- `PBIRWriter.psm1`: write only geometry and verify.
- `UndoService.psm1`: restore latest backup.
- `Logging.psm1`: user-local logs.
- `PreviewCanvas.psm1`: render schematic before/after previews.
- `MainForm.psm1`: WinForms orchestration only.

Do not move core layout logic into button click handlers.

## Smart-layout behavior

V1 should infer the current page rather than requiring a manual column count.

Use visual geometry to detect approximate tracks with tolerance. Misaligned positions that are close must collapse into the same row/column. Estimate standard peer width/height robustly (median is preferred). Infer large visual column/row spans from geometry and detected tracks.

The final proposal must be deterministic for the same input + settings.

Default settings:

```text
Margin = 5
Gap = 5
Tolerance = Auto
Mode = Smart Align
```

If the engine cannot confidently produce a non-overlapping in-bounds result, disable Apply and show why instead of guessing.

## File-write safety

Before Apply:

- ensure selected visual files still exist;
- validate proposed layout;
- calculate which visuals actually change;
- create an operation backup outside the project;
- require confirmation.

During Apply:

- preserve unrelated JSON text as much as practical;
- update only position x/y/width/height;
- write through a temporary file;
- parse the temporary JSON;
- verify target geometry;
- replace the original;
- remove temporary files.

On any write failure, restore the backup and surface the error.

After Apply:

- re-read visual files;
- validate geometry;
- log the operation;
- enable Undo.

## Tests

Do not require Pester. `tests/Run-V1-Tests.ps1` must run with stock Windows PowerShell 5.1.

Automated test must create its own temporary enhanced-PBIR fixture and cover:

- project discovery;
- page order/display name;
- visual geometry read;
- row/column detection;
- span detection;
- smart layout;
- no overlaps/out-of-bounds;
- backup creation;
- geometry-only write;
- write re-read;
- undo;
- cleanup.

Never mark the Power BI Desktop manual test as PASS unless a human actually runs it. Record manual results in `docs/V1-Test-Checklist.md`.

## Completion rule

Do not claim V1 is completed merely because files exist in GitHub.

Use these states:

- **Implemented** — code exists.
- **Automated test passed** — test executed successfully on Windows PowerShell 5.1.
- **Manual PBIR test passed** — tested on real report files.
- **Power BI Desktop verified** — project opens/reloads and renders correctly.
- **V1 release-ready** — all above are true.

V2/V3 remain out of scope until explicitly supplied by the user.
