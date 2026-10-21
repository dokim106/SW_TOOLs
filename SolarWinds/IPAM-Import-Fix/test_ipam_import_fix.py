#!/usr/bin/env python3
"""Regression tests for ipam_import_fix.py — run before shipping any edit to the fixer.

    python3 test_ipam_import_fix.py          # quiet unless something fails
    python3 test_ipam_import_fix.py -v       # list every case

Every case is a real defect that was found and fixed, or a contract the fixer must keep:
the Import sheet may only ever hold values SolarWinds IPAM accepts, no input row may vanish
without a reason in Rejected, the input file is never modified, and nothing may raise.
Adding a case: append to CASES (name, builder, checks) — builders write a fixture into tmp.
"""
from __future__ import annotations

import ipaddress
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "ipam_import_fix.py")
STATUS = {"Used", "Available", "Reserved", "Transient"}   # "Blocked"/"API Blocked" is set by IPAM, never imported
MAC_RE = re.compile(r"^[0-9A-F]{2}([:-][0-9A-F]{2}){5}$")
CTRL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

try:
    import openpyxl
except ImportError:
    sys.exit("openpyxl missing: pip3 install openpyxl")


# ---------------------------------------------------------------- helpers
def xlsx(path, rows, sheet="Sheet1", extra_sheets=None):
    wb = openpyxl.Workbook(); ws = wb.active; ws.title = sheet
    for r in rows:
        ws.append(list(r))
    for name, rws in (extra_sheets or {}).items():
        w2 = wb.create_sheet(name)
        for r in rws:
            w2.append(list(r))
    wb.save(path); return path


def csvf(path, text, encoding="utf-8", newline=""):
    with open(path, "w", encoding=encoding, newline=newline) as fh:
        fh.write(text)
    return path


def run(inp, *args):
    out = os.path.join(os.path.dirname(inp), "out_" + os.path.basename(os.path.splitext(inp)[0]) + ".xlsx")
    before = os.path.getmtime(inp), os.path.getsize(inp)
    p = subprocess.run([sys.executable, SCRIPT, inp, "-o", out, *args], capture_output=True, text=True)
    after = os.path.getmtime(inp), os.path.getsize(inp)
    assert before == after, "the fixer modified its input file"
    assert "Traceback" not in (p.stdout + p.stderr), "crashed:\n" + p.stdout + p.stderr
    sheets = {}
    if os.path.exists(out):
        wb = openpyxl.load_workbook(out)
        for nm in ("Import", "Rejected", "Report"):
            if nm in wb.sheetnames:
                sheets[nm] = [list(r) for r in wb[nm].iter_rows(values_only=True)]
    return p, sheets


def imp(sheets):
    """Import sheet as a list of dicts."""
    rows = sheets.get("Import") or []
    if not rows:
        return []
    hdr = [h for h in rows[0]]
    return [{h: ("" if v is None else str(v)) for h, v in zip(hdr, r)} for r in rows[1:]]


def contract(sheets, ctx):
    """Every Import value must be something IPAM accepts."""
    for i, rec in enumerate(imp(sheets), start=2):
        if "IP Address" in rec:
            assert rec["IP Address"], f"{ctx}: empty IP on Import row {i}"
            ipaddress.ip_address(rec["IP Address"])
        if rec.get("Status"):
            assert rec["Status"] in STATUS, f"{ctx}: bad Status {rec['Status']!r}"
        if rec.get("MAC Address"):
            assert MAC_RE.match(rec["MAC Address"]), f"{ctx}: bad MAC {rec['MAC Address']!r}"
        if rec.get("Subnet CIDR"):
            assert rec["Subnet CIDR"].isdigit(), f"{ctx}: CIDR not an integer: {rec['Subnet CIDR']!r}"
        if rec.get("Subnet Address") and rec.get("Subnet CIDR"):
            net = ipaddress.ip_network(f"{rec['Subnet Address']}/{rec['Subnet CIDR']}", strict=False)
            assert str(net.network_address) == rec["Subnet Address"], f"{ctx}: subnet not normalised"
        for v in rec.values():
            assert not CTRL_RE.search(v), f"{ctx}: control character reached Import"


# ---------------------------------------------------------------- cases
def case_short_and_long_rows(tmp):
    """CRASH 2026-09-03: rows shorter than the header raised IndexError; data past the last header was dropped."""
    f = csvf(os.path.join(tmp, "short.csv"), "IP Address,Status,Comments\n10.4.4.1\n10.4.4.2,used\n10.4.4.3,used,ok,EXTRA\n")
    p, sh = run(f)
    recs = imp(sh)
    assert len(recs) == 3, f"expected 3 rows, got {len(recs)}"
    assert recs[0]["Status"] == "Available", "missing Status must default"
    assert any("past the last header" in str(r) for r in sh["Report"]), "extra column must be reported, not dropped silently"


def case_fake_xlsx(tmp):
    """CRASH: a CSV renamed .xlsx raised BadZipFile."""
    f = csvf(os.path.join(tmp, "fake.xlsx"), "IP Address,Status\n10.5.5.1,used\n")
    p, sh = run(f)
    assert len(imp(sh)) == 1
    assert any("not an Excel file" in str(r) for r in sh["Report"])


def case_control_chars(tmp):
    """CRASH: control characters in a source cell reached the Report sheet -> IllegalCharacterError."""
    f = csvf(os.path.join(tmp, "ctrl.csv"), "IP Address,Status,DNS\n192.0.2.5\x01,Used,\n192.0.2.6,Used,host\x0bname\n")
    p, sh = run(f)
    contract(sh, "control chars")
    assert len(imp(sh)) == 2


def case_excel_damage(tmp):
    """IPs mangled by Excel must be recovered, not rejected."""
    f = xlsx(os.path.join(tmp, "damage.xlsx"), [
        ["IP Address", "Status", "MAC Address"],
        ["010.001.001.007", "FREE", "aa-bb-cc-dd-ee-01"],
        [167837960, "reserved", "aabb.ccdd.eeff"],
        [" 192.0.2.6 ", "In Use", "AABBCCDDEE02"],
        ["192.0.2.30/32", "Assigned", "zz:zz"],
    ])
    p, sh = run(f)
    contract(sh, "excel damage")
    ips = [r["IP Address"] for r in imp(sh)]
    assert ips == ["192.0.2.7", "192.0.2.8", "192.0.2.6", "192.0.2.30"], ips
    macs = [r["MAC Address"] for r in imp(sh)]
    assert macs[:3] == ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:FF", "AA:BB:CC:DD:EE:02"], macs
    assert macs[3] == "", "an unreadable MAC must be blanked, never passed through"


def case_ranges_and_subnets(tmp):
    """Ranges expand; a subnet in the IP column expands and fills Subnet Address/CIDR."""
    f = xlsx(os.path.join(tmp, "ranges.xlsx"), [
        ["IP Address", "Status"],
        ["192.0.2.10-192.0.2.13", "dhcp"],
        ["192.0.2.20 - 22", "available"],
        ["10.1.2.0/30", ""],
    ])
    p, sh = run(f)
    contract(sh, "ranges")
    recs = imp(sh)
    assert len(recs) == 4 + 3 + 2, f"expected 9 expanded rows, got {len(recs)}"
    assert all(r["Status"] == "Transient" for r in recs[:4])
    sub = [r for r in recs if r["IP Address"].startswith("10.1.2.")]
    assert sub and sub[0]["Subnet Address"] == "10.1.2.0" and sub[0]["Subnet CIDR"] == "30"


def case_subnet_mode(tmp):
    """Masks convert, host bits move to the network address, unusable rows are rejected with a reason."""
    f = xlsx(os.path.join(tmp, "subnets.xlsx"), [
        ["Network", "Mask", "VLAN", "Site"],
        ["192.0.2.0", "255.255.255.0", "VLAN 10", "HQ"],
        ["10.1.2.5", "/30", "20", "HQ"],
        ["10.1.3.0/24", "", "", "DC"],
        ["10.1.4.0", "", "", "DC"],
        ["bad", "24", "", ""],
    ])
    p, sh = run(f, "--mode", "subnets")
    contract(sh, "subnets")
    recs = imp(sh)
    assert len(recs) == 3, f"expected 3 subnets, got {len(recs)}"
    assert recs[1]["Subnet Address"] == "10.1.2.4", "host bits must move to the network address"
    assert recs[0]["VLAN"] == "10", "VLAN must reduce to its number"
    reasons = [r[1] for r in (sh.get("Rejected") or [])[1:]]
    assert len(reasons) == 2 and any("CIDR" in str(x) for x in reasons) and any("invalid IP" in str(x) for x in reasons)


def case_available_must_be_empty(tmp):
    """IPAM rule (SDK + THWACK red-hostname thread): Alias/MAC/hostname/comments must be EMPTY when Status is Available."""
    rows = [["IP Address", "Status", "hostname", "MAC", "Comments"],
            ["192.0.2.5", "available", "srv01.corp", "aa-bb-cc-dd-ee-01", "phone"],   # assigned -> promote
            ["192.0.2.6", "", "srv02.corp", "", "no status but named"],               # smart default -> Used
            ["192.0.2.7", "", "", "", "truly free"],                                  # comment only -> stays Available
            ["192.0.2.8", "blocked", "", "", "not settable"]]                         # API Blocked -> Reserved
    f = xlsx(os.path.join(tmp, "avail.xlsx"), rows)
    # default is flag: an explicit status the operator set is reported, never rewritten (research spec R9)
    p, sh = run(f)
    contract(sh, "available")
    recs = imp(sh)
    assert [r["Status"] for r in recs] == ["Available", "Used", "Available", "Reserved"], [r["Status"] for r in recs]
    assert recs[0]["DNS"] == "srv01.corp", "flag must keep the data"
    assert any("redden" in str(x) or "Available row carried" in str(x) for x in sh["Report"]), "the clash must be reported"
    assert recs[2]["Comments"] == "truly free", "a comment alone must never be dropped or flip the status"
    # promote resolves it in favour of the data
    p, sh = run(f, "--available-conflict", "promote")
    assert [r["Status"] for r in imp(sh)] == ["Used", "Used", "Available", "Reserved"], [r["Status"] for r in imp(sh)]
    p, sh = run(f, "--available-conflict", "clear")
    recs = imp(sh)
    assert recs[0]["Status"] == "Available" and recs[0]["DNS"] == "" and recs[0]["MAC Address"] == "", recs[0]
    for r in imp(sh):
        assert r["Status"] != "Blocked", "Blocked is not settable in IPAM and must never be emitted"


def case_structure_sheet_rules(tmp):
    """Structure Type vocabulary, Y/N columns never blank, and 'Name' meaning the subnet's name."""
    f = xlsx(os.path.join(tmp, "struct.xlsx"), [
        ["Type", "Network", "CIDR", "Name", "Retain User Data", "Disable Auto Scanning"],
        ["subnets", "192.0.2.0", "24", "HQ", "", ""],
        ["folder", "10.2.0.0", "16", "Campus", "y", ""],
    ])
    p, sh = run(f, "--mode", "subnets")
    recs = imp(sh)
    assert [r["Type"] for r in recs] == ["Subnet", "Group"], [r["Type"] for r in recs]
    assert [r["Subnet Name"] for r in recs] == ["HQ", "Campus"], "a structure 'Name' is the subnet name, not an IP alias"
    for r in recs:
        for b in ("Retain User Data", "Disable Auto Scanning"):
            assert r[b] in ("Y", "N"), f"{b} must never be blank: {r[b]!r}"
    assert recs[1]["Retain User Data"] == "Y"
    assert any("larger than /20" in str(x) for x in sh["Report"]), "the 4096-address display threshold must be reported"


def case_markup_and_orphans(tmp):
    """<tags> are swallowed by IPAM's description renderer; addresses outside every declared subnet orphan."""
    f = xlsx(os.path.join(tmp, "orph.xlsx"), [
        ["IP Address", "Status", "Comments", "Subnet", "CIDR"],
        ["192.0.2.5", "used", "was <VoIP> phone", "192.0.2.0", "24"],
        ["10.9.9.9", "used", "elsewhere", "192.0.2.0", "24"],
    ])
    p, sh = run(f)
    recs = imp(sh)
    assert recs[0]["Comments"] == "was [VoIP] phone", recs[0]["Comments"]
    assert any("orphan" in str(x) for x in sh["Report"]), "an address outside every declared subnet must be reported"


def case_version_traps(tmp):
    f = csvf(os.path.join(tmp, "ver.csv"), "IP Address,Status\n192.0.2.1,used\n")
    p, sh = run(f, "--ipam-version", "2026.1")
    report = " ".join(str(x) for x in sh["Report"])
    assert "2026.1" in report, "version-specific traps must appear in the report"
    assert "Overlapping with Subnet" in report, "the create-not-update trap must always be reported"


def case_mac_format_option(tmp):
    f = csvf(os.path.join(tmp, "macfmt.csv"), "IP Address,Status,MAC\n192.0.2.1,used,aabb.ccdd.eeff\n")
    p, sh = run(f, "--mac-format", "hyphen")
    assert imp(sh)[0]["MAC Address"] == "AA-BB-CC-DD-EE-FF", imp(sh)[0]


def case_dedupe_modes(tmp):
    rows = [["IP Address", "Status", "Comments"], ["10.9.9.1", "used", "first"], ["10.9.9.1", "reserved", "second"]]
    f = xlsx(os.path.join(tmp, "dupe.xlsx"), rows)
    for mode, expect_rows, expect_comment in (("keep-first", 1, "first"), ("keep-last", 1, "second"), ("flag", 2, "first")):
        p, sh = run(f, "--dedupe", mode)
        recs = imp(sh)
        assert len(recs) == expect_rows, f"{mode}: expected {expect_rows} rows, got {len(recs)}"
        assert recs[0]["Comments"] == expect_comment, f"{mode}: kept the wrong row"


def case_nothing_vanishes(tmp):
    """Every data row ends up in Import (possibly expanded) or in Rejected with a reason."""
    f = xlsx(os.path.join(tmp, "account.xlsx"), [
        ["IP Address", "Status"],
        ["192.0.2.1", "used"], ["10.1.1", "used"], ["", "used"], ["not an ip", "used"], ["192.0.2.2", "used"],
    ])
    p, sh = run(f)
    kept = len(imp(sh)); rejected = len(sh.get("Rejected", [])) - 1
    assert kept + rejected == 5, f"5 rows in, {kept} kept + {rejected} rejected"
    for r in (sh["Rejected"] or [])[1:]:
        assert r[1], "a rejected row must carry a reason"


def case_delimiter_under_title_row(tmp):
    """DEFECT 2026-09-03: csv.Sniffer saw a title line first and read a ;-file as one column -> 'no header row found'."""
    for name, delim in (("semi_title.csv", ";"), ("tab_title.csv", "\t"), ("pipe_title.csv", "|")):
        f = csvf(os.path.join(tmp, name),
                 "IPAM export - site B\r\n\r\n"
                 + delim.join(["ip addr", "Status", "host name"]) + "\r\n"
                 + delim.join([" 010.2.3.4 ", "IN USE", "srv1.corp.local."]) + "\r\n")
        p, sh = run(f)
        recs = imp(sh)
        assert len(recs) == 1, f"{name}: expected 1 row, got {len(recs)}"
        assert recs[0]["IP Address"] == "10.2.3.4" and recs[0]["Status"] == "Used" and recs[0]["DNS"] == "srv1.corp.local", recs


def case_encodings(tmp):
    for name, enc, text in (
        ("bom.csv", "utf-8-sig", "IP Address,Status,Comments\n10.7.7.1,used,café\n"),
        ("cp1252.csv", "cp1252", "IP Address,Status,Comments\n10.7.7.2,used,café\n"),
        ("utf16.csv", "utf-16", "IP Address,Status\n10.7.7.3,used\n"),
        ("semi.csv", "utf-8", "IP Address;Status\n10.7.7.4;used\n"),
        ("tab.csv", "utf-8", "IP Address\tStatus\n10.7.7.5\tused\n"),
    ):
        f = csvf(os.path.join(tmp, name), text, encoding=enc)
        p, sh = run(f)
        contract(sh, name)
        assert len(imp(sh)) == 1, f"{name}: expected 1 row"


def case_header_discovery(tmp):
    """A title banner and blank rows above the header must not hide it."""
    f = xlsx(os.path.join(tmp, "title.xlsx"), [
        ["IPAM import — site A"], [],
        ["ip address ", "Status", "hostname"],
        ["10.3.3.1", "used", "srv.corp.local."],
    ])
    p, sh = run(f)
    recs = imp(sh)
    assert len(recs) == 1 and recs[0]["DNS"] == "srv.corp.local", recs


def case_idempotent(tmp):
    """Re-running the fixer on its own output must change nothing."""
    f = xlsx(os.path.join(tmp, "idem.xlsx"), [["IP Address", "Status", "MAC Address"], ["10.8.8.1", "used", "aa-bb-cc-dd-ee-01"]])
    p1, sh1 = run(f)
    out1 = os.path.join(tmp, "out_idem.xlsx")
    p2, sh2 = run(out1)
    assert imp(sh1) == imp(sh2), "second pass changed the data"
    fixes = [r for r in sh2["Report"] if r and r[0] and str(r[0]) not in ("ipam_import_fix report", "mode", "rows written", "rows rejected", "fix", "note", "Source row")]
    assert not fixes, f"second pass still reported fixes: {fixes}"


def case_empty_and_headeronly(tmp):
    for name, text in (("empty.csv", ""), ("hdr.csv", "IP Address,Status\n"), ("blanks.csv", "IP Address,Status\n,\n,\n")):
        f = csvf(os.path.join(tmp, name), text)
        p = subprocess.run([sys.executable, SCRIPT, f, "-o", os.path.join(tmp, "o_" + name + ".xlsx")], capture_output=True, text=True)
        assert "Traceback" not in p.stdout + p.stderr, f"{name} crashed:\n{p.stdout}{p.stderr}"


def case_strict_exit_code(tmp):
    f = csvf(os.path.join(tmp, "strict.csv"), "IP Address,Status\n192.0.2.1,used\nnonsense,used\n")
    p = subprocess.run([sys.executable, SCRIPT, f, "-o", os.path.join(tmp, "o_strict.xlsx"), "--strict"], capture_output=True, text=True)
    assert p.returncode != 0, "--strict must exit non-zero when rows are rejected"
    assert "Traceback" not in p.stdout + p.stderr


def case_no_overwrite(tmp):
    """The INPUT is sacred and is never written to. The tool's own previous output IS
    replaced by default (2026-09-03: folder mode re-runs were multiplying files
    _ipam_fixed-2, -3, -4 ... forever); --keep-versions restores the old versioning."""
    import hashlib
    f = xlsx(os.path.join(tmp, "keep.xlsx"), [["IP Address", "Status"], ["10.6.6.1", "used"]])
    src_md5 = hashlib.md5(open(f, "rb").read()).hexdigest()
    first = os.path.join(tmp, "keep_ipam_fixed.xlsx")

    subprocess.run([sys.executable, SCRIPT, f], capture_output=True, text=True)
    assert os.path.exists(first)
    stamp = os.path.getmtime(first)

    # default: replaces its own output, no -2 litter
    time.sleep(1.1)
    subprocess.run([sys.executable, SCRIPT, f], capture_output=True, text=True)
    assert os.path.getmtime(first) != stamp, "default must refresh the existing output"
    assert not os.path.exists(os.path.join(tmp, "keep_ipam_fixed-2.xlsx")), \
        "default must not accumulate versioned outputs"

    # --keep-versions: old behaviour still available
    subprocess.run([sys.executable, SCRIPT, f, "--keep-versions"], capture_output=True, text=True)
    assert os.path.exists(os.path.join(tmp, "keep_ipam_fixed-2.xlsx")), \
        "--keep-versions must write a -2 file"

    # the input never changes, under any of those runs
    assert hashlib.md5(open(f, "rb").read()).hexdigest() == src_md5, "the INPUT file was modified"

    # and -o aimed straight at the input still cannot clobber it
    subprocess.run([sys.executable, SCRIPT, f, "-o", f, "--csv"], capture_output=True, text=True)
    assert hashlib.md5(open(f, "rb").read()).hexdigest() == src_md5, "-o pointing at the input overwrote it"


def case_structure_export(tmp):
    """IPAM's OWN structure export must be read as a SUBNET import. Its address column is
    called plain "Address", which aliases to IP Address, so before 2026-09-03 a real export
    (the operator's) came through as mode=ips: a Status column was invented for every subnet, Type
    Subnet/Supernet was rejected as not Static/Dynamic, and subnets sharing an address were
    dropped as duplicates (31 rows in, 28 out)."""
    hdr = ("Id,Address,CIDR,Type,Display Name,ParentId,Group Description,Node Expunge Interval,"
           "Retain User Data,Transient Period,Disable Auto Scanning,Disable Neighbor Scanning,"
           "VLAN,Location,Scan Interval,Neighbor Scan Address,Neighbor Scan Interval,ExportFileName")
    body = [
        "1,157.207.65.0,24,Subnet,Aberdeen Public IP,0,157.207.65.0 /24,,False,,False,True,,,240,,240,Aberdeen_3929",
        "2,157.207.66.0,24,Subnet,Aberdeen Public IP,0,157.207.66.0 /24,,False,,False,True,,,240,,240,Aberdeen_3930",
        "3,157.207.32.0,22,Supernet,EGYPT Public,0,157.207.32.0 /22,,False,,False,True,,,,,,",
    ]
    f = os.path.join(tmp, "Structure.csv")
    with open(f, "w", encoding="utf-8-sig") as fh:      # real exports carry a BOM
        fh.write(hdr + "\n" + "\n".join(body) + "\n")

    p, sh = run(f)
    out = p.stdout
    assert "mode: subnets" in out, f"structure export not detected as subnets:\n{out}"
    rows = imp(sh)
    assert len(rows) == 3, f"rows lost: {len(rows)} of 3"

    cols = set(rows[0])
    assert "Subnet Address" in cols, f"Address did not become Subnet Address: {sorted(cols)}"
    assert "IP Address" not in cols, f"structure rows were written as host addresses: {sorted(cols)}"
    assert "Subnet Name" in cols, f"Display Name did not become Subnet Name: {sorted(cols)}"
    assert "Status" not in cols, "a Status column was invented on a structure import"

    assert rows[0]["Subnet Address"] == "157.207.65.0" and rows[0]["Subnet CIDR"] == "24"
    assert rows[0]["Subnet Name"] == "Aberdeen Public IP"
    assert rows[2]["Type"] == "Supernet", f"structure Type mangled: {rows[2].get('Type')}"
    # False/True must land as IPAM's Y/N, not as the words
    assert rows[0]["Retain User Data"] == "N" and rows[0]["Disable Neighbor Scanning"] == "Y", rows[0]

    # and the IP-sheet meaning of Address is NOT disturbed
    g = xlsx(os.path.join(tmp, "hosts.xlsx"), [["Address", "Status"], ["10.4.4.1", "used"]])
    p2, sh2 = run(g)
    assert "mode: ips" in p2.stdout, "a plain address sheet was mistaken for structure"
    assert "IP Address" in set(imp(sh2)[0]), "Address stopped meaning IP Address on an IP sheet"


def case_batch_folder(tmp):
    """A folder is fixed in one run, and EVERY data sheet in a workbook is converted -
    a workbook holding addresses plus a structure/subnet sheet must not lose the structure
    half (2026-09-03: only the first sheet was converted and the rest were silently dropped)."""
    d = os.path.join(tmp, "batchdir"); os.makedirs(d, exist_ok=True)
    xlsx(os.path.join(d, "hosts.xlsx"), [["IP Address", "Status"], ["10.9.9.1", "used"]])
    # one workbook, two sheets: IP addresses AND structure
    import openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active; ws.title = "IPs"
    for r in [["IP Address", "Status"], ["10.9.8.1", "used"]]:
        ws.append(r)
    st = wb.create_sheet("Structure")
    for r in [["Subnet Address", "Subnet CIDR", "Subnet Name"], ["10.9.7.0", "24", "lab"]]:
        st.append(r)
    both = os.path.join(d, "mixed.xlsx"); wb.save(both)
    with open(os.path.join(d, "notes.txt"), "w") as fh:
        fh.write("not a spreadsheet\n")

    r = subprocess.run([sys.executable, SCRIPT, d], capture_output=True, text=True)
    produced = sorted(n for n in os.listdir(d) if "_ipam_fixed" in n)
    assert os.path.exists(os.path.join(d, "hosts_ipam_fixed.xlsx")), f"single-sheet file not fixed: {produced}"
    assert os.path.exists(os.path.join(d, "mixed_IPs_ipam_fixed.xlsx")), f"IP sheet not fixed: {produced}"
    assert os.path.exists(os.path.join(d, "mixed_Structure_ipam_fixed.xlsx")), \
        f"STRUCTURE sheet was dropped: {produced}"

    # the structure output really is subnet mode, not an IP sheet
    wb2 = openpyxl.load_workbook(os.path.join(d, "mixed_Structure_ipam_fixed.xlsx"))
    hdr = [c for c in next(wb2["Import"].iter_rows(values_only=True)) if c]
    assert "Subnet Address" in hdr, f"structure output has the wrong columns: {hdr}"

    # a re-run must not fix its own outputs, and must not multiply them
    before = sorted(os.listdir(d))
    subprocess.run([sys.executable, SCRIPT, d], capture_output=True, text=True)
    assert sorted(os.listdir(d)) == before, "re-running the folder changed the file set"


def case_ipv6(tmp):
    f = xlsx(os.path.join(tmp, "v6.xlsx"), [["IP Address", "Status"],
                                            ["2001:db8:0000:0000:0000:0000:0000:0001", "blocked"],
                                            ["fe80::1%eth0", "used"]])
    p, sh = run(f)
    contract(sh, "ipv6")
    ips = [r["IP Address"] for r in imp(sh)]
    assert ips == ["2001:db8::1", "fe80::1"], ips


CASES = [v for k, v in sorted(globals().items()) if k.startswith("case_")]


def main():
    verbose = "-v" in sys.argv
    tmp = tempfile.mkdtemp(prefix="ipamfix-test-")
    failed = []
    try:
        for fn in CASES:
            name = fn.__name__[5:]
            try:
                fn(tmp)
                if verbose:
                    print(f"  ok    {name}")
            except AssertionError as e:
                failed.append((name, str(e))); print(f"  FAIL  {name}: {e}")
            except Exception as e:
                failed.append((name, repr(e))); print(f"  ERROR {name}: {e!r}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"{len(CASES) - len(failed)}/{len(CASES)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
