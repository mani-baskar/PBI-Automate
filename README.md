# PBI Automate

Open-source Windows automation toolkit for Power BI PBIP projects.

> **Development status:** V1 is under active development on `dev/v1-smart-layout`. The `main` branch is intentionally kept clean until V1 has passed Windows + Power BI Desktop manual verification.

## V1 — Smart Layout

V1 focuses on one job: safely clean up a rough Power BI report page layout stored in enhanced PBIR.

It can:

- open a `.pbip`, PBIP project folder, or `.Report` folder;
- resolve the report through PBIP artifact paths when available;
- discover report pages and show their display names;
- read visual `x`, `y`, `width`, and `height`;
- detect approximate rows, columns, and large visual spans;
- preview a proposed aligned layout;
- use a default 5-unit page margin and 5-unit gap;
- validate page bounds and overlaps;
- create a backup before any write;
- update only supported visual geometry in `visual.json`;
- re-read and verify the written geometry;
- undo the latest apply operation;
- keep activity logs under the current user's local application-data folder.

V1 does **not** edit DAX, TMDL, relationships, queries, filters, visual bindings, bookmarks, themes, mobile layouts, or unrelated formatting.

## Requirements

- Windows
- Windows PowerShell 5.1
- .NET Framework / WinForms available with Windows
- A Power BI Project using enhanced PBIR (`<Report>.Report/definition/pages`)

No Python, Node.js, .NET SDK, PowerShell Gallery module, admin rights, internet connection, or installer is required.

Corporate Windows policies may block unsigned PowerShell scripts. PBI Automate does not bypass execution policy; use your organization's approved signing/allow-list process if required.

## Run

Clone/download this development branch and double-click:

```text
Start-PBIAutomate.cmd
```

Or from Windows PowerShell:

```powershell
.\Start-PBIAutomate.ps1
```

Workflow:

1. Choose the PBIP file or report folder.
2. Select a report page.
3. Click **Analyze Page**.
4. Review **Before** and **After** previews.
5. Confirm validation passed.
6. Click **Apply Layout**.
7. Reload/open the project in Power BI Desktop.
8. Use **Undo Last Apply** if the result is not desired.

## V1 automated integration test

The repository includes a dependency-free Windows PowerShell test that creates a temporary synthetic PBIR project and runs the complete core flow:

```powershell
.\tests\Run-V1-Tests.ps1
```

The test covers project discovery, page/visual reading, row/column analysis, smart-layout calculation, validation, backup, write verification, and undo.

The current expanded CI suite contains **52 automated assertions** and runs on Windows PowerShell 5.1.

This automated test does not replace the Power BI Desktop manual test. See [docs/V1-Status.md](docs/V1-Status.md) for current progress and follow [docs/V1-Test-Checklist.md](docs/V1-Test-Checklist.md) before declaring V1 release-ready.

## Project structure

```text
PBI-Automate/
├─ Start-PBIAutomate.cmd
├─ Start-PBIAutomate.ps1
├─ AGENTS.md
├─ config/
├─ docs/
├─ src/
│  ├─ Core/
│  └─ UI/
└─ tests/
```

Core logic is deliberately separated from WinForms so future services can reuse the same PBIP/PBIR engine.

## Safety

PBI Automate is designed around preview → validate → backup → write → re-read/verify.

Backups are stored outside the PBIP project under:

```text
%LOCALAPPDATA%\PBIAutomate\Backups
```

Logs are stored under:

```text
%LOCALAPPDATA%\PBIAutomate\Logs
```

Always use source control for important PBIP projects.

## Roadmap

V1 is intentionally limited to Smart Layout. V2 and V3 requirements will be added only after V1 is completed and frozen.

## Trademark notice

PBI Automate is an independent open-source community project and is not affiliated with or endorsed by Microsoft. Power BI and Microsoft Fabric are trademarks of Microsoft Corporation.
