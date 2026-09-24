# PBI Automate - Architecture

PBI Automate is a portable Windows PowerShell 5.1 + WinForms desktop toolkit for Power BI PBIP automation.

The application is designed as a **software shell with independent services**. The common PBIP project infrastructure is shared. Each automation feature owns its own service folder, core logic and future UI-specific options.

## Application shell

The WinForms shell is intentionally stable as new services are added:

1. **Common Project Bar**
   - PBIP project selector
   - detected report
   - page selector
   - Refresh to re-read files after a manual Power BI save
2. **Service Navigation**
   - Alignment Correction
   - Change Format - Coming Soon
   - Theme Creation - Coming Soon
   - Visual Copy Paste - Coming Soon
3. **Selected Service Options**
   - service-specific settings and commands live above the service content
4. **Service Content / Preview**
   - Alignment uses Before / After preview
   - future services own their own content area
5. **Processing Footer**
   - common activity log and status remain visible for every service

## Folder ownership

```text
src/
├─ Core/
│  ├─ ConfigService.psm1
│  ├─ Logging.psm1
│  ├─ ProjectDiscovery.psm1
│  ├─ PBIRReader.psm1
│  ├─ BackupService.psm1
│  ├─ PBIRWriter.psm1
│  └─ UndoService.psm1
├─ Services/
│  ├─ ServiceRegistry.psm1
│  ├─ Alignment/
│  │  ├─ AlignmentService.psm1
│  │  └─ Core/
│  │     ├─ AlignmentAnalyzer.psm1
│  │     ├─ AlignmentLayoutEngine.psm1
│  │     └─ AlignmentValidator.psm1
│  ├─ Formatting/
│  ├─ Theme/
│  └─ VisualCopyPaste/
└─ UI/
   ├─ MainForm.psm1
   └─ PreviewCanvas.psm1
```

### Shared Core

Shared Core knows how to find PBIP/PBIR files, read report definitions, create backups, write safe geometry changes, undo operations and log activity.

Shared Core must not contain feature-specific business rules.

### Services

A service owns feature-specific logic.

**Alignment Correction** currently owns:
- visual topology analysis;
- area-preserving layout calculation;
- top/left anchor priority;
- gap/margin handling;
- bounds and overlap validation;
- service-level preview/apply/undo orchestration.

Future formatting/theme/copy-paste logic must go into its own service folder instead of growing MainForm or Alignment.

### UI

MainForm owns only the reusable application shell and event wiring. Business logic is delegated to service functions.

PreviewCanvas renders schematic visual rectangles and does not modify report files.

## V1 safety boundary

Alignment V1 may change only:
- position.x
- position.y
- position.width
- position.height

It must not change TMDL, DAX, relationships, queries, bindings, filters, bookmarks, themes, mobile layouts or unrelated visual formatting.

## Development branch

`dev/v1-smart-layout`

The public `main` branch remains untouched until the current release is manually verified.
