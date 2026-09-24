# V1 Manual Test Checklist

Do not mark V1 release-ready until this checklist is executed on Windows with a real Power BI PBIP project using enhanced PBIR.

## Test environment

Record:

- Date:
- Windows version:
- Windows PowerShell version (`$PSVersionTable.PSVersion`):
- Power BI Desktop version:
- Test report/project:
- Tester:

## A. Automated integration test

Run:

```powershell
.\tests\Run-V1-Tests.ps1
```

Expected: exit code 0 and all assertions PASS.

Result: [ ] PASS [ ] FAIL  
Notes:

## B. Launch / project discovery

1. Double-click `Start-PBIAutomate.cmd`.
2. Confirm WinForms opens.
3. Browse to a valid `.pbip`.
4. Confirm the correct `.Report` folder is detected.
5. Confirm page names appear.
6. Repeat by selecting the `.Report` folder directly.
7. Try an unsupported/invalid folder and confirm the tool stops safely.

Result: [ ] PASS [ ] FAIL  
Notes:

## C. Page analysis

Use a page with multiple intentionally rough visuals, including at least one wide or tall visual.

Confirm:

- [ ] Visual count is reasonable.
- [ ] Before preview resembles current layout.
- [ ] Rows/columns detected match the intended structure.
- [ ] Large visual span is preserved.
- [ ] Default margin is 5.
- [ ] Default gap is 5.
- [ ] Proposed layout has no overlaps.
- [ ] Proposed layout stays inside canvas.
- [ ] Apply is disabled if validation fails.

Result: [ ] PASS [ ] FAIL  
Notes:

## D. Apply safety

Before Apply, commit/stash the PBIP project in Git if possible.

1. Analyze and preview.
2. Click Apply.
3. Confirm the confirmation dialog appears.
4. Confirm a backup folder is created under `%LOCALAPPDATA%\PBIAutomate\Backups`.
5. Check Git diff.

The diff must show only intended `position.x`, `position.y`, `position.width`, and `position.height` changes in targeted `visual.json` files.

It must not alter DAX/TMDL, bindings, filters, formatting, bookmarks, themes, or unrelated files.

Result: [ ] PASS [ ] FAIL  
Notes:

## E. Power BI Desktop verification

1. Open/reload the PBIP project in Power BI Desktop.
2. Open the modified page.
3. Confirm visuals render.
4. Confirm fields/measures/filters still work.
5. Confirm visuals are aligned and sized as previewed.
6. Confirm intended large visual structure remains.
7. Save/reopen the project once more.

Result: [ ] PASS [ ] FAIL  
Notes:

## F. Undo

1. Close/reload Power BI if needed to avoid file locks.
2. Click Undo Last Apply.
3. Confirm the most recent PBI Automate backup is restored.
4. Compare the restored visual files to the pre-apply Git state.
5. Confirm the restored project opens in Power BI Desktop.

Result: [ ] PASS [ ] FAIL  
Notes:

## G. Edge cases

Test at minimum:

- [ ] Page with 1 visual.
- [ ] Page with 2–4 visuals.
- [ ] Page with a wide visual.
- [ ] Page with a tall visual.
- [ ] Page with many visuals.
- [ ] Visual positions containing decimals.
- [ ] Hidden visual/container if present.
- [ ] Non-standard custom visual if present.
- [ ] Invalid JSON should fail safely.
- [ ] Read-only/locked visual file should fail and restore backup.
- [ ] No `.pbiautomate.tmp` files remain after success/failure.

## Release gate

V1 can be merged to `main` only after:

- [ ] Automated integration test passed on Windows PowerShell 5.1.
- [ ] Real PBIR manual test passed.
- [ ] Power BI Desktop verification passed.
- [ ] Undo was verified.
- [ ] Git diff showed geometry-only changes.
- [ ] No known data-loss/report-corruption issue remains.
