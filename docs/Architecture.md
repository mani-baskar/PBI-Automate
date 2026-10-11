# PBI Automate - Architecture

PBI Automate is a portable Windows PowerShell 5.1 + WinForms desktop toolkit for Power BI PBIP automation.

The application is designed as a **software shell with independent services**. The common PBIP project infrastructure is shared. Each automation feature owns its own service folder, core logic and UI-specific options.

## Application shell

The WinForms shell is intentionally stable as new services are added:

1. **Common Project Bar**
   - PBIP project selector
   - detected report
   - page selector
   - Refresh to re-read files after a manual Power BI save
2. **Service Navigation**
   - Alignment Correction
   - Analyse
   - Change Format - Coming Soon
   - Theme Creation - Coming Soon
   - Visual Copy Paste - Coming Soon
3. **Selected Service Options**
   - service-specific settings and commands live above the service content
4. **Service Content / Preview**
   - Alignment uses Before / After preview
   - Analyse uses model scan / Markdown-generation workspace
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
│  │     ├─ AlignmentValidator.psm1
│  │     └─ OverlapResolver.psm1
│  ├─ Analyse/
│  │  ├─ AnalyseService.psm1
│  │  ├─ AnalyseView.psm1
│  │  └─ Core/
│  │     ├─ SemanticModelDiscovery.psm1
│  │     ├─ TmdlReader.psm1
│  │     ├─ SourceInspector.psm1
│  │     └─ MarkdownWriter.psm1
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

### Alignment service

**Alignment Correction** owns:
- visual topology analysis;
- deterministic layout calculation;
- overlap normalization;
- gap/margin handling;
- bounds and overlap validation;
- service-level preview/apply/undo orchestration.

Alignment is a mutating service. Its write boundary remains geometry-only: x, y, width and height.

### Analyse service

**Analyse** is read-only against the selected PBIP project. It resolves the local semantic model through `definition.pbir -> datasetReference.byPath`, with sibling `.SemanticModel` fallback for compatible projects.

Analyse owns:
- TMDL table discovery;
- physical and calculated column inventory;
- measure DAX extraction;
- calculated-table DAX extraction;
- partition mode and Power Query M extraction;
- Power Query connector and connection-target detection;
- native SQL detection/extraction;
- relationship inventory and Mermaid flow generation;
- report-page inventory;
- Markdown documentation generation;
- credential-like value redaction in generated documentation.

Generated output is deliberately outside the PBIP definition tree unless the user chooses otherwise:

```text
<chosen output>/
└─ Analyse/
   ├─ README.md
   ├─ Table/
   │  ├─ _index.md
   │  └─ <TableName>.md
   ├─ Relationship/
   │  └─ Relationships.md
   └─ Pages/
      └─ README.md
```

Long SQL, Power Query M, DAX and raw TMDL sections use Markdown `<details>` blocks so rendered documentation stays compact by default.

Analyse must never modify TMDL, DAX, relationships, queries or report definitions.

### UI

`MainForm.psm1` owns the reusable application shell. Feature-specific UI extensions stay with their services; Analyse uses `AnalyseView.psm1` and business logic stays in `AnalyseService.psm1` / `Core` modules.

`PreviewCanvas.psm1` renders schematic visual rectangles and does not modify report files.

## Safety boundaries

### Alignment

Alignment may change only:
- position.x
- position.y
- position.width
- position.height

It must not change TMDL, DAX, relationships, queries, bindings, filters, bookmarks, themes, mobile layouts or unrelated visual formatting.

### Analyse

Analyse is read-only. It may only read PBIP/PBIR/TMDL files and create documentation under the selected output directory. Credential-like values must be redacted before they are written to generated Markdown.

## Tests

- `tests/Run-V1-Tests.ps1` covers the existing Alignment V1 flow on stock Windows PowerShell 5.1.
- `tests/Run-Analyse-Tests.ps1` covers semantic-model discovery, TMDL parsing, documentation generation and Analyse UI attachment.
- `tests/Run-Analyse-SourceTests.ps1` covers native SQL, measure DAX, server/database/file target extraction and redaction.

No Pester or external PowerShell modules are required.

## Development branches

- Alignment base: `dev/v1-smart-layout`
- Analyse development: `dev/v1-model-analysis`

The public `main` branch remains untouched until features are manually verified and intentionally promoted.
