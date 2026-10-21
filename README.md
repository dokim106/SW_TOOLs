# SW_TOOLs

SolarWinds Orion tooling and generic dashboard/report helpers built in the lab. Scripts and templates only — no client data, no vendor installers, no environment-specific hostnames.

## SolarWinds/

- `IPAM-Import-Fix/` — InfoBlox IPAM import fixer: normalizes subnet/IP CSVs into one import-ready sheet (Import / Rejected / Report), every cell stored as TEXT so Excel cannot re-mangle IPs. `ipam_import_fix.py` (CLI), `test_ipam_import_fix.py`, `ipam_gui_wrapper.py`.
- `SWQL_Modules/` — curated SWQL query library by module (NPM, SAM, NCM, IPAM, VMAN, ORION Platform) with a `main.ps1` runner.
- `SWQL_KnowledgeBase/` — SWQL/SWIS reference: schemas, SWIS PowerShell patterns, per-module cookbooks, upgrade/HA notes.
- `SWIS/Dashboard-Import-GUI/` — import a Modern Dashboard export: file picker, one-line JSON for SWQL Studio, shows where the dashboard and its `/customdash` page files land, page check, import via SWIS REST (credentials entered per run, nothing stored). `Fix-CustomDash-VDir.ps1` adds the `/customdash` IIS mapping.
- SAM/RDP helpers — `SAM-PowerShell-Monitor-Setup-Checklist.md`, `Test-SamRemoteExec.ps1`, `Set-RDP.ps1`, `backup sam templates.ps1`, `BackupApplicationTemplates.ps1`.
- Misc — `osquery_checks.ps1`, `Group Availability.txt`, `Containers.csv` (sample), `spin_wheel_widget.js` (dashboard widget), `export/import dashboards.ps1`, `import templatest.ps1`, sample text outputs, `DB_Tests/`, `NTM_Install/`, `Migration_Templates/`.

## arcade/

Self-contained arcade dashboard (DOOM via wasm, 2048) for the Orion console: copy `games/` to the custom-dash folder on the web server, import `arcade.json` as a custom dashboard.

## Excluded by design

Client data, case exports, monthly comparison PDFs, work-process tools, report templates, built exe/app binaries, and vendor ISOs are not in this repo.
