# Analyse Service

`Analyse` is the read-only semantic-model documentation service in PBI Automate.

## Input

The service starts from the PBIP/report already selected in the common project bar. It resolves the local semantic model primarily from:

```text
<Report>.Report/definition.pbir
  -> datasetReference.byPath.path
  -> <Model>.SemanticModel/
```

If that path is unavailable, a compatible single/matching sibling `*.SemanticModel` folder can be used as a fallback.

## Output

The default output root is the folder containing the selected `.pbip` file. The user can select another folder.

```text
Analyse/
├─ README.md
├─ Table/
│  ├─ _index.md
│  └─ <TableName>.md
├─ Relationship/
│  └─ Relationships.md
└─ Pages/
   └─ README.md
```

## Table Markdown

Each table document includes:

- overview and object counts;
- connector/source type;
- connection targets such as server/database, file path, SharePoint/Web URL when discoverable from M;
- partition type and mode;
- Power Query step inventory;
- native SQL detection and extracted query when possible;
- full Power Query M in collapsed `<details>`;
- calculated-table DAX in collapsed `<details>`;
- column inventory;
- calculated-column DAX in collapsed `<details>`;
- measure inventory and measure DAX in collapsed `<details>`;
- optional shared Power Query expressions/parameters referenced by the table;
- raw TMDL in a collapsed block.

## Relationships

`Relationship/Relationships.md` contains a relationship inventory plus a Mermaid `flowchart LR` model diagram. Inactive relationships use a dashed arrow.

## Pages

V1 creates a page inventory with canvas size and active/hidden/group visual counts. Deeper page-to-table / visual lineage is intentionally a later Analyse phase.

## Code ownership

- `AnalyseService.psm1` - orchestration and output-folder creation.
- `AnalyseView.psm1` - Analyse-specific WinForms workspace.
- `Core/SemanticModelDiscovery.psm1` - report-to-semantic-model resolution.
- `Core/TmdlReader.psm1` - TMDL parsing.
- `Core/SourceInspector.psm1` - connector target extraction and redaction.
- `Core/MarkdownWriter.psm1` - Markdown rendering.

## Safety

Analyse does not edit the report or semantic model. It only reads project files and writes generated documentation to the chosen output folder. Credential-like values are redacted from generated text where detected.
