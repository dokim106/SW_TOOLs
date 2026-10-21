# Dashboard-Import-GUI

A small window for importing a SolarWinds Modern Dashboard export. Windows PowerShell 5.1, no OrionSDK needed
(it talks to the SWIS REST API on port 17774).

## Run

Double-click `Start-Import-Dashboard.cmd`, or:

```
powershell -ExecutionPolicy Bypass -File .\Import-Dashboard-GUI.ps1
```

1. **Browse...** and pick the exported dashboard JSON.
2. **Where it goes** shows, for that file:
   - the dashboard: imported into SolarWinds by the SWIS verb `Orion.Dashboards.Instances.Import`, then under
     *My Dashboards* in the console;
   - each embedded page widget (`/customdash/<name>/...`): the folder its page files must be in on the
     SolarWinds **web** server, `C:\CustomDash\<name>\`, and the address it is served at.
3. **Copy / Save 1-line JSON**: the same dashboard on one line, for SWQL Studio
   (`Orion.Dashboards.Instances` > `Import` > *Invoke*, paste it as the argument).
4. Enter the **server, username and password** and press **Import into SolarWinds**. The password stays in the
   window only; nothing is saved.
5. **Check page** asks the web server for the widget's page without signing in:
   - `302` (sent to the login page): the page is there and protected.
   - `404`: the page files are not in the folder from step 2, or IIS has no `/customdash` mapping.
     Run `Fix-CustomDash-VDir.ps1` elevated on the web server. Adding the mapping restarts the Orion web app,
     so the console is slow for a few minutes afterwards.

## Notes

- A dashboard whose key already exists is updated in place. If it was edited in the console the import fails:
  delete it in the console first.
- *Trust the server's own certificate* is on by default because SWIS ships a self-signed certificate.
- `arcade.dashboard.oneline.json` is the Arcade dashboard (`../../../arcade/dashboard.json`) as one line. Its page
  files are `arcade/dist/`, copied to `C:\CustomDash\arcade\` on the web server.

## Tested

Windows PowerShell 5.1 against a SolarWinds Platform 2026.1 lab, with `-SelfTest <file>`: window built, 1-line JSON
identical to the file, destinations, page check (`302`), and SWIS reachable (a wrong password is refused).
A full import with real credentials has not been run through this tool yet.
