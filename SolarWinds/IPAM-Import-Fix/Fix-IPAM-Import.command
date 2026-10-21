#!/usr/bin/env bash
# Double-click: pick a FOLDER; every spreadsheet in it is fixed for SolarWinds IPAM import.
# Each sheet becomes <name>_ipam_fixed.xlsx (+ .csv) beside its source. Sources are never modified.
# A workbook holding both addresses and a structure/subnet sheet yields one output per sheet,
# because IPAM imports structure and addresses separately.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(osascript -e 'POSIX path of (choose folder with prompt "Folder of spreadsheets to fix for IPAM import")' 2>/dev/null)
if [ -z "$T" ]; then
  # cancelled the folder picker: offer a single file instead rather than doing nothing
  T=$(osascript -e 'POSIX path of (choose file with prompt "…or pick a single spreadsheet" of type {"xlsx","xlsm","csv","txt"})' 2>/dev/null)
fi
[ -z "$T" ] && { echo "nothing chosen"; exit 0; }
echo "fixing: $T"; echo
python3 "$DIR/ipam_import_fix.py" "$T" --csv
rc=$?
echo
case $rc in
  0) echo "done — no rejected rows." ;;
  2) echo "done, but some rows were REJECTED. Open the Rejected sheet in each output before importing." ;;
  3) echo "one or more files FAILED to convert (listed above)." ;;
  *) echo "exited with code $rc" ;;
esac
# reveal what was actually produced, newest first (never a stale earlier run)
if [ -d "$T" ]; then REVEAL="$T"; else REVEAL="$(dirname "$T")"; fi
NEWEST=$(ls -1t "$REVEAL"/*_ipam_fixed.xlsx 2>/dev/null | head -1)
if [ -n "$NEWEST" ]; then open -R "$NEWEST"; else open "$REVEAL"; fi
read -r -p "press return to close"
