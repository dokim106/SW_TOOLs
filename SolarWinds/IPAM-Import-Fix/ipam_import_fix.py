#!/usr/bin/env python3
"""ipam_import_fix.py — make an Excel/CSV sheet importable by SolarWinds IPAM (subnets or IP addresses).

Usage:
  ipam_import_fix.py INPUT.xlsx|.csv [-o OUT.xlsx] [--mode auto|ips|subnets] [--sheet NAME] [--csv]
                     [--default-status Available] [--available-conflict flag|promote|clear]
                     [--mac-format colon|hyphen] [--comment-max N] [--ipam-version 2026.1]
                     [--no-expand-ranges] [--dedupe keep-first|keep-last|flag] [--strict] [--quiet]

Writes <input>_ipam_fixed.xlsx with three sheets — Import (paste-ready, every cell stored as TEXT so Excel
cannot re-mangle an IP), Rejected (every row that could not be fixed, with its reason AND all its original
values), and Report (what changed, the column mapping the wizard will ask you to confirm, and the IPAM traps
that apply). --csv also writes a plain CSV of the Import sheet. The input file is never written to.

What it fixes
  • finds the real header row even under a title banner or a merged group-header row, maps header aliases to
    IPAM's own column names, keeps unknown columns as custom properties, and never lets a repeated column
    overwrite the validated value;
  • cells: trims, deletes zero-width/bidi marks, turns exotic spaces into spaces, recovers numbers, dates and
    formulas, blanks Excel error values (#VALUE! etc.);
  • IP Address: repairs Excel damage (32-bit integers, leading zeros, "10 .1.1.5", "10,1,1,5", /32 suffix,
    IPv6 compression), NEVER deletes characters from inside an address, expands "a-b" ranges, and treats
    "192.0.2.5/24" as one host carrying its mask rather than as 254 addresses;
  • Subnet: mask → CIDR (CIDR wins when they disagree, and it says so), "/24" → 24, host bits → network
    address, IPv4 and IPv6 prefixes both valid;
  • Status: synonyms → the exact IPAM spelling (Used, Available, Reserved, Transient). "Blocked" is never
    emitted — IPAM sets API Blocked itself. A row with a hostname/MAC but NO status becomes Used, because
    calling it Available would break IPAM's rule that an available address carries no data. A row that
    EXPLICITLY says Available while carrying data is reported, not rewritten (--available-conflict changes that);
  • structure sheets: Type spelled as IPAM writes it; a blank Y/N cell is reported, never invented, because
    the documented remedy is to map that column to [Do not import];
  • MAC → AA:BB:CC:DD:EE:FF (or hyphens); hostnames trimmed; <tags> in comments → [tags]; VLAN → integer;
  • duplicates (keep-first / keep-last / flag), orphaned addresses, and the version-specific IPAM traps.

Requires Python 3.9+ and openpyxl (pip install openpyxl). CSV needs nothing extra.
Regression suite: `python3 test_ipam_import_fix.py` — 21 cases, each one a defect that was found and fixed or
a contract this script must keep. Run it before shipping any edit here.

The rules come from the SolarWinds IPAM Administrator Guide, the Success Center KBs, the Orion SDK schema and
THWACK threads; the tables at the top of this file (HEADER_ALIASES, STATUS_MAP, STRUCTURE_TYPES, VERSION_TRAPS)
carry the citations and are the only place to edit when a future IPAM release changes something.
the operator / OurTeam work tool, 2026-09-03.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import ipaddress
import os
import re
import sys
from collections import Counter, OrderedDict

# ----------------------------------------------------------------------------------------------------
# Canonical column names (what IPAM's import wizard auto-maps) and the aliases seen in the wild.
# Keys are canonical; values are lower-case aliases (matched after trimming/collapsing spaces/underscores).
# ----------------------------------------------------------------------------------------------------
HEADER_ALIASES: "OrderedDict[str, list[str]]" = OrderedDict([
    ("IP Address",        ["ip address", "ip", "ipaddress", "ip addr", "address", "ipv4", "ipv4 address", "ipv6 address", "host ip", "ip_address", "ipaddr", "node ip"]),
    ("Status",            ["status", "ip status", "state", "usage", "used", "allocation", "allocated"]),
    ("Alias",             ["alias", "friendly name", "display name", "name", "label", "device", "device name"]),
    ("MAC Address",       ["mac address", "mac", "macaddress", "mac addr", "hardware address", "hw address", "physical address"]),
    ("DNS",               ["dns", "dns name", "hostname", "host name", "fqdn", "dns hostname", "reverse dns", "ptr", "host", "dnsbackward"]),
    ("Comments",          ["comments", "comment", "notes", "note", "description", "remarks", "desc"]),
    ("Skip Scan",         ["skip scan", "skipscan", "skip", "no scan", "exclude from scan", "do not scan"]),
    ("Machine Type",      ["machine type", "machinetype", "device type"]),
    # "Type" means different things per sheet: object class on a structure sheet (Group/Subnet/...),
    # alloc policy on an IP sheet (Static/Dynamic). Validated per mode, never guessed across.
    ("Type",              ["type", "object type", "alloc policy", "allocation policy", "allocpolicy"]),
    ("Vendor",            ["vendor", "manufacturer", "make"]),
    ("System Name",       ["system name", "sysname", "sys name"]),
    ("System Description", ["system description", "sysdescr", "sys description", "sysdesc"]),
    ("System Contact",    ["system contact", "syscontact", "contact", "owner"]),
    ("System Location",   ["system location", "syslocation"]),
    ("DHCP Client Name",  ["dhcp client name", "dhcp name", "client name", "dhcp client"]),
    ("Subnet Address",    ["subnet address", "subnet", "network", "network address", "net", "subnet ip", "subnet/cidr", "subnet cidr address", "prefix", "cidr block", "network/cidr"]),
    ("Subnet CIDR",       ["subnet cidr", "cidr", "prefix length", "prefixlen", "mask bits", "bits", "/"]),
    ("Subnet Mask",       ["subnet mask", "mask", "netmask", "net mask"]),
    ("Subnet Name",       ["subnet name", "subnetname", "network name", "vlan name", "segment", "site subnet"]),
    ("VLAN",              ["vlan", "vlan id", "vlanid", "vlan number", "vid"]),
    ("Location",          ["location", "site", "site name", "building", "datacenter", "dc", "office"]),
    ("Group",             ["group", "parent group", "parent", "folder", "container", "ipam group", "supernet"]),
    # structure-sheet booleans — the KB names them with the accepted values inside the header itself
    ("Retain User Data",  ["retain user data", "retain user data (y/n)", "retain data", "retainuserdata"]),
    ("Disable Auto Scanning", ["disable auto scanning", "disable auto scanning (y/n)", "disable scanning", "no auto scan"]),
    ("Disable Neighbor Scanning", ["disable neighbor scanning", "disable neighbour scanning", "disable neighbor scanning (y/n)"]),
])

# The four settable IP statuses, exactly as the IPAM Administrator Guide spells them, with the synonyms
# people write in spreadsheets. There IS a fifth status, "API Blocked" — the guide says you cannot set it
# manually, so this script never emits it; rows that say blocked/excluded become Reserved and are reported.
#   doc: documentation.solarwinds.com .../ipam-set-an-ip-address-status-to-available...
STATUS_MAP = {
    "Used":      ["used", "in use", "inuse", "active", "assigned", "allocated", "taken", "occupied", "live", "up", "yes", "u"],
    "Available": ["available", "free", "unused", "unassigned", "empty", "open", "spare", "avail", "no", "a", "none", ""],
    "Reserved":  ["reserved", "reserve", "res", "hold", "held", "r"],
    "Transient": ["transient", "dhcp", "dynamic", "lease", "leased", "temp", "temporary", "t"],
}
STATUS_VALUES = list(STATUS_MAP)
NOT_SETTABLE = {"blocked", "block", "api blocked", "blacklisted", "excluded", "exclude", "do not use", "dnu", "forbidden", "b"}

# IPAM's own validation (Orion SDK, IPAM.IPNode CRUD): on a row whose Status is Available, Alias, MAC,
# DnsBackward (hostname), DhcpClientName, IPMapped and Comments must all be empty. A sheet that carries a
# hostname on an "available" row is invalid, and this is the documented diagnosis for the classic THWACK
# symptom of the wizard reddening the hostname column on a subset of rows.
#   doc: solarwinds.github.io/OrionSDK/docs/ipam-2019-4-and-higher-versions-api/
#   thread: thwack.solarwinds.com/discussion/36498/import-validation-errors
AVAILABLE_MUST_BE_EMPTY = ["Alias", "MAC Address", "DNS", "Comments", "DHCP Client Name"]
# ...but only these say "this address is actually assigned". A comment alone ("reserved for expansion")
# is not evidence of use, so it never flips a status to Used — it is flagged instead.
ASSIGNED_EVIDENCE = ["Alias", "MAC Address", "DNS", "DHCP Client Name"]

# Structure-sheet object classes, read from the Type column of the official example structure spreadsheet.
STRUCTURE_TYPES = ["Subnet", "Group", "Supernet", "IPv6Subnet", "PrefixAggregate", "GlobalPrefix"]
STRUCTURE_TYPE_SYNONYMS = {"subnets": "Subnet", "groups": "Group", "supernets": "Supernet",
                           "ipv6 subnet": "IPv6Subnet", "ipv6 subnets": "IPv6Subnet", "ipv6 site": "IPv6Subnet",
                           "ipv6 sites": "IPv6Subnet", "global prefix": "GlobalPrefix", "global prefixes": "GlobalPrefix",
                           "prefix aggregate": "PrefixAggregate", "network": "Subnet", "folder": "Group"}
# IP-sheet Type / alloc policy. The literals come from the SDK's IPAllocPolicy enum; SolarWinds does not
# document that the spreadsheet importer accepts these strings, so unknown values are left alone + flagged.
# IPAM's own structure export carries these columns and an IP-address sheet never does. Two or more of
# them means the sheet is structure, whatever the address column happens to be called. Without this,
# "Address"/"CIDR" alias to IP Address/Subnet CIDR, the sheet is read as an IP import, a Status column is
# invented for every subnet and rows collapse as "duplicates" (found on the operator's real export, 2026-09-03).
STRUCTURE_SIGNATURE = {
    "retain user data", "disable auto scanning", "disable neighbor scanning", "parentid", "parent id",
    "group description", "node expunge interval", "transient period", "scan interval",
    "neighbor scan address", "neighbor scan interval", "exportfilename", "export file name",
    "display name", "subnet type",
}
# Columns whose meaning flips on a structure sheet: "Address" is the subnet's network address there,
# not a host address, and the display name is the subnet's name, not an IP alias.
STRUCTURE_REMAP = {"IP Address": "Subnet Address", "Alias": "Subnet Name"}


def structure_score(headers) -> int:
    return sum(1 for h in headers if h and norm_header(h) in STRUCTURE_SIGNATURE)


ALLOC_POLICIES = ["Static", "Dynamic"]

# Behaviour that differs by IPAM version. These are reported, never silently worked around — the column
# contract itself is identical in the 2020.2.1 and 2026.2 Administrator Guides.
VERSION_TRAPS = [
    ("4.2",    "IPAM 4.2: the sample spreadsheets served by the web UI are the same file for both types. Take the real ones from the polling engine: <DRIVE>\\inetpub\\SolarWinds\\Orion\\IPAM\\res\\"),
    ("4.x",    "IPAM 4.x: the wizard has been observed mapping subnet fields to the wrong parent. Pilot on one small subnet and verify in the UI before a bulk run — the green Import Summary is not proof."),
    ("4.6",    "IPAM 4.6+: subnets IPAM originally learned from DHCP will not accept import updates. Change those through the UI or the Orion SDK."),
    ("2026.1", "IPAM 2026.1: the structure validator has been reported objecting to Group rows that legitimately have a blank Address. If validation fails on Group rows, this is the known cause."),
    ("all",    "Every version: the spreadsheet import CREATES, it does not update. Re-importing existing subnets fails with 'Overlapping with Subnet'; use the Orion SDK for updates."),
    ("all",    "Every version: overwrite is the default and there is no dry-run. Export the target subnets first so you have a rollback."),
    ("all",    "Every version: a scan after the import can revert imported values it cannot confirm. Set Skip Scan on rows that will not answer a ping, or mark them Reserved."),
    ("all",    "Every version: re-importing an IPAM export fails with 'COMMAND FAILED: An item with the same key has already been added' when the structure sheet's TAB is named 'Structure.xls'. Rename the tab to 'Structure'."),
    ("all",    "Every version: in a multi-worksheet workbook the header row must be byte-identical on every sheet."),
]

IP_COLS = {"IP Address", "Status", "Alias", "MAC Address", "DNS", "Comments", "Skip Scan", "Machine Type", "Vendor",
           "System Name", "System Description", "System Contact", "System Location", "DHCP Client Name",
           "Subnet Address", "Subnet CIDR"}
SUBNET_COLS = {"Subnet Address", "Subnet CIDR", "Subnet Name", "VLAN", "Location", "Comments", "Group"}

# SolarWinds publishes NO maximum length for Comments / Alias / hostname (the SWIS schema pages list no
# MaxLength and the IPAM database schema is not public). These are conservative safety caps, not documented
# limits — every truncation is reported, and --comment-max raises the comment cap.
COMMENT_MAX = 4000
ALIAS_MAX = 255
HOSTNAME_MAX = 255
RANGE_MAX = 4096            # a single "a-b" range bigger than this is rejected rather than expanded silently

# DELETED outright (never turned into a space): zero-width and bidi marks, which otherwise rewrite a
# hostname into a different name and stop a status from matching.
ZERO_WIDTH = re.compile(r"[\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff\u00ad]")
# turned into a space: real (if exotic) spaces, plus control characters
BAD_CHARS = re.compile(r"[\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
XL_ERRORS = {"#VALUE!", "#REF!", "#N/A", "#DIV/0!", "#NAME?", "#NULL!", "#NUM!", "#SPILL!", "#CALC!"}
WS = re.compile(r"\s+")


# ----------------------------------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------------------------------
DETAIL_MAX = 20000          # per-cell change rows kept for the Report sheet; the counts stay complete


class Report:
    def __init__(self):
        self.fixes = Counter()
        self.rows = []          # (row, column, before, after, note) — capped at DETAIL_MAX
        self.detail_dropped = 0
        self.rejects = []       # (row, reason, original row dict)
        self.warnings = []      # sheet-level notes

    def fix(self, row, col, before, after, note):
        self.fixes[note] += 1   # the count is always exact
        if len(self.rows) >= DETAIL_MAX:
            self.detail_dropped += 1        # a million-row sheet must not grow the change log without bound
            return
        self.rows.append((row, col, "" if before is None else str(before), "" if after is None else str(after), note))

    def reject(self, row, reason, original, custom=None):
        self.fixes["rejected: " + reason] += 1
        full = dict(original)
        for k, v in (custom or {}).items():
            full.setdefault(k, v)
        self.rejects.append((row, reason, full))

    def warn(self, text):
        if text not in self.warnings:
            self.warnings.append(text)


def clean_text(v) -> str:
    """Any cell -> clean string. Numbers/dates/bools become text; junk characters removed."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "Yes" if v else "No"
    if isinstance(v, float):
        if v.is_integer():
            return str(int(v))
        return repr(v)
    if isinstance(v, (dt.datetime, dt.date, dt.time)):
        return v.isoformat(sep=" ") if isinstance(v, dt.datetime) else str(v)
    s = str(v)
    s = ZERO_WIDTH.sub("", s)                   # delete, do not turn into a space
    s = BAD_CHARS.sub(" ", s)
    s = s.replace("\r", " ").replace("\n", " ")
    s = WS.sub(" ", s).strip()
    if s.startswith("="):                       # a formula that came through as text
        s = s.lstrip("=").strip()
    if s.startswith("'"):                       # Excel's "treat as text" prefix
        s = s[1:].strip()
    return s


def cell_value(v, col, rownum, rep):
    """clean_text plus the two things that must never reach the Import sheet as data."""
    s = clean_text(v)
    if s in XL_ERRORS:
        rep.fix(rownum, col, s, "", "Excel error value blanked — fix the formula in the source")
        return ""
    if s == "#FORMULA#":
        rep.fix(rownum, col, "formula", "", "formula with no calculated value blanked (open the file in Excel and save)")
        return ""
    return s


def norm_header(h) -> str:
    s = clean_text(h).lower()
    s = re.sub(r"[_\-\.\*:#]+", " ", s)
    s = re.sub(r"\(.*?\)", "", s)               # "IP Address (required)" -> "ip address"
    return WS.sub(" ", s).strip()


def canonical_header(h):
    n = norm_header(h)
    if not n:
        return None
    for canon, aliases in HEADER_ALIASES.items():
        if n == canon.lower() or n in aliases:
            return canon
    # tolerant: "ip address 1", "ipaddress*"
    n2 = re.sub(r"\s*\d+$", "", n)
    for canon, aliases in HEADER_ALIASES.items():
        if n2 == canon.lower() or n2 in aliases:
            return canon
    return None


def parse_ip(text: str):
    """Return (ip_obj, note) — repairs Excel/human damage. None if the cell is not exactly one address.

    Characters are NEVER deleted from inside an address: doing that turned "192.0.2.5 #2" into 192.0.2.52,
    a real address belonging to a different host (found 2026-09-03). An address is extracted by pattern and
    anything left over is reported or rejected.
    """
    s = clean_text(text)
    if not s:
        return None, "empty"
    if s == "#FORMULA#":
        return None, "formula without a calculated value (open in Excel and save, or paste values)"
    raw = s
    note = None
    s = s.replace(",", ".") if re.fullmatch(r"\d{1,3}(,\d{1,3}){3}", s) else s     # 10,1,1,5
    s = re.sub(r"\s+", "", s) if re.fullmatch(r"[\d\s.]+", s) else s               # 10 .1.1.5

    # Excel turned an IP into a 32-bit integer. Only accept it when the result is a sane unicast address,
    # otherwise an asset tag or ticket number becomes 0.x.x.x.
    if re.fullmatch(r"\d{7,10}", s):
        try:
            cand = ipaddress.ip_address(int(s))
            if not (cand.is_unspecified or cand.is_loopback or cand.is_multicast or cand.is_reserved
                    or int(cand) < 0x01000000):
                return cand, "ip recovered from a 32-bit integer (verify: the source cell was a number)"
        except ValueError:
            pass
        return None, f"{raw!r} is a bare number, not an address (an IP saved as a number would decode outside the usable range)"

    # exactly one address, with an optional prefix; anything else in the cell is leftover text
    m = re.fullmatch(r"\s*([0-9a-fA-F:.]+)(?:%[\w.]+)?(/\d{1,3})?\s*", s)
    if not m:
        m2 = re.search(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b", s)
        if not m2:
            return None, f"invalid IP address ({raw!r})"
        rest = (s[:m2.start()] + s[m2.end():]).strip(" ,;|/()[]-")
        ip, sub_note = parse_ip(m2.group(1))
        if ip is None:
            return None, f"invalid IP address ({raw!r})"
        return ip, f"extra text {rest[:30]!r} dropped from the IP cell — check it" if rest else "ip cleaned"

    body, pfx = m.group(1), m.group(2)
    if "%" in raw:
        note = "zone id removed"
    if pfx:
        bits = int(pfx[1:])
        host_only = (body.count(":") == 0 and bits == 32) or (body.count(":") and bits == 128)
        if host_only:
            note = f"/{bits} suffix removed"
        # any other prefix is handled by the caller (host+mask vs network), so keep the address only here
    if re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", body):
        parts = body.split(".")
        if any(len(x) > 1 and x.startswith("0") for x in parts):
            body = ".".join(str(int(x)) for x in parts); note = note or "leading zeros removed"
    try:
        ip = ipaddress.ip_address(body)
    except ValueError:
        return None, f"invalid IP address ({raw!r})"
    if note is None and str(ip) != raw:
        note = "IPv6 compressed" if ip.version == 6 else "ip cleaned"
    return ip, note


def split_prefix(text: str):
    """'192.0.2.5/24' -> (ip, 24) ; '192.0.2.0/24' -> (ip, 24). Returns (None, None) when there is no prefix."""
    s = clean_text(text).replace(" ", "")
    m = re.fullmatch(r"([0-9a-fA-F:.]+)/(\d{1,3})", s)
    if not m:
        return None, None
    ip, _ = parse_ip(m.group(1))
    if ip is None:
        return None, None
    bits = int(m.group(2))
    if bits > (32 if ip.version == 4 else 128):
        return None, None
    return ip, bits


def parse_cidr(text: str, ipver=None):
    """'24' / '/24' / '255.255.255.0' -> int prefix. ipver=None accepts anything valid for v4 or v6."""
    s = clean_text(text).lstrip("/").strip()
    if not s:
        return None
    if re.fullmatch(r"\d{1,3}", s):
        n = int(s)
        top = 128 if ipver in (None, 6) else 32
        return n if 0 <= n <= top else None
    try:
        return ipaddress.ip_network(f"0.0.0.0/{s}").prefixlen           # dotted mask
    except ValueError:
        return None


_STATUS_NOISE = re.compile(r"[\'\"`]|\(.*?\)|\[.*?\]")


def normalise_status(text: str, default: str, row_has_data: bool):
    """-> (Status, note). A row with a hostname/MAC but no status is assigned, not free: it defaults to Used,
    because calling it Available would break IPAM's own Available-must-be-empty rule."""
    raw = clean_text(text)
    s = _STATUS_NOISE.sub(" ", raw).lower().strip(". ")
    s = re.sub(r"[-_/]+", " ", s)
    s = WS.sub(" ", s).strip()
    for canon, syns in STATUS_MAP.items():
        if s == canon.lower() or s in syns:
            if s == canon.lower() and raw == canon:
                return canon, None
            if not s:
                break
            return canon, "status normalised"
    if s in NOT_SETTABLE:
        return "Reserved", f"status {raw!r} is not settable in IPAM (API Blocked is set by IPAM itself) -> Reserved"
    # "reserved for VIP", "used - static", "in use by dhcp": take the leading word when it is unambiguous
    first = s.split(" ")[0] if s else ""
    for canon, syns in STATUS_MAP.items():
        if first and (first == canon.lower() or first in syns):
            return canon, f"status {raw!r} read as {canon}"
    if first in NOT_SETTABLE:
        return "Reserved", f"status {raw!r} is not settable in IPAM -> Reserved"
    if not s:
        d = "Used" if row_has_data else default
        return d, f"no status -> {d}" + (" (the row carries host data, so it is not free)" if row_has_data else "")
    d = "Used" if row_has_data else default
    return d, f"unknown status {raw!r} -> {d} — check it"


def normalise_mac(text: str):
    s = clean_text(text)
    if not s:
        return "", None
    hexs = re.sub(r"[^0-9a-fA-F]", "", s)
    if len(hexs) != 12:
        return "", f"invalid MAC {s!r} blanked"
    sep = "-" if MAC_FORMAT[0] == "hyphen" else ":"
    mac = sep.join(hexs[i:i + 2] for i in range(0, 12, 2)).upper()
    return mac, (None if mac == s else "MAC normalised")


# The wizard's on-screen hint shows 00-19-AA-80-3C-0C, the shipped template shows 00:0A:E6:3E:FD:E1 and the
# API mandates colons. Colon is the best-supported form; --mac-format hyphen switches it.
MAC_FORMAT = ["colon"]


def strip_markup(text, col, rownum, rep):
    """<VoIP> in a description is saved but never rendered (THWACK: IPAM Description field). Use brackets."""
    if text and "<" in text and ">" in text:
        out = re.sub(r"<([^<>]*)>", r"[\1]", text)
        if out != text:
            rep.fix(rownum, col, text[:60], out[:60], "angle brackets replaced with square brackets (IPAM swallows <tags> on display)")
        return out
    return text


def normalise_bool(text: str):
    s = clean_text(text).lower()
    if s in ("yes", "y", "true", "t", "1", "x", "✓", "skip"):
        return "Yes"
    if s in ("no", "n", "false", "f", "0", ""):
        return "No"
    return None


def expand_range(text: str):
    """'192.0.2.1-192.0.2.50', '192.0.2.1 - 50', '192.0.2.1..192.0.2.9', '192.0.2.0/28' (in an IP cell) -> list of IPs or None."""
    s = clean_text(text).replace(" ", "")
    m = re.fullmatch(r"(\d{1,3}(?:\.\d{1,3}){3})(?:-|\.\.|–|—|to)(\d{1,3}(?:\.\d{1,3}){3}|\d{1,3})", s)
    if not m:
        return None
    a = parse_ip(m.group(1))[0]
    if a is None:
        return None
    b_txt = m.group(2)
    if "." not in b_txt:
        b_txt = ".".join(str(a).split(".")[:3] + [b_txt])
    b = parse_ip(b_txt)[0]
    if b is None or int(b) < int(a):
        return None
    if int(b) - int(a) + 1 > RANGE_MAX:
        return "too-big"
    return [ipaddress.ip_address(i) for i in range(int(a), int(b) + 1)]


# ----------------------------------------------------------------------------------------------------
# reading
# ----------------------------------------------------------------------------------------------------
def read_rows(path: str, sheet: str | None, rep: Report):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".xlsx", ".xlsm", ".xltx", ".xltm"):
        try:
            import openpyxl
        except ImportError:
            sys.exit("openpyxl is missing: pip3 install openpyxl")
        try:
            wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
        except Exception as exc:
            if "zip" in str(exc).lower() or exc.__class__.__name__ == "BadZipFile":
                rows = _read_delimited(path, rep)
                if not any(canonical_header(clean_text(c)) for r in rows[:50] for c in r):
                    sys.exit(f"{os.path.basename(path)} is not a readable Excel file and has no recognisable "
                             "header as text either — it looks damaged. Open it in Excel and re-save.")
                rep.warn(f"{os.path.basename(path)} is named .xlsx but is not an Excel file; read as delimited text")
                return rows, os.path.basename(path)
            sys.exit(f"cannot open {os.path.basename(path)}: {exc}")
        names = wb.sheetnames
        if sheet:
            pick = next((n for n in names if n == sheet), None) \
                or next((n for n in names if n.strip().lower() == sheet.strip().lower()), None)
            if pick is None:
                sys.exit(f"no worksheet named {sheet!r}. This workbook has: {', '.join(names)}")
            ws = wb[pick]
        else:
            # skip leading sheets that hold no recognisable header rather than aborting on an empty one
            ws = wb[names[0]]
            for n in names:
                probe = [[c for c in r] for r in wb[n].iter_rows(max_row=50, values_only=True)]
                if any(canonical_header(clean_text(c)) for r in probe for c in r):
                    ws = wb[n]; break
            if ws.title != names[0]:
                rep.warn(f"sheet '{names[0]}' has no recognisable header; used '{ws.title}' instead")
        if len(names) > 1:
            rep.warn(f"workbook has {len(names)} sheets ({', '.join(names)}); used '{ws.title}' — pass --sheet to pick another")
            # IPAM: "If your file has multiple worksheets, the header rows must be identical in each worksheet."
            try:
                base = [str(c.value or "").strip() for c in next(ws.iter_rows(max_row=1))]
                for nm in names:
                    if nm == ws.title:
                        continue
                    other = [str(c.value or "").strip() for c in next(wb[nm].iter_rows(max_row=1), [])]
                    if other and other != base:
                        rep.warn(f"sheet '{nm}' has a DIFFERENT header row from '{ws.title}' — IPAM requires every "
                                 "worksheet in a workbook to share one identical header row; import them as separate files")
                        break
            except Exception:
                pass
        if ws.title.lower().endswith((".xls", ".xlsx", ".csv")):
            rep.warn(f"the worksheet TAB is named '{ws.title}' — an IPAM export names it 'Structure.xls' and re-importing "
                     "then fails with 'COMMAND FAILED: An item with the same key has already been added'. Rename the tab to 'Structure'.")
        rows = [list(r) for r in ws.iter_rows(values_only=True)]
        # hidden rows are still imported; say so rather than letting one beat a visible row in de-duplication
        try:
            wbv = openpyxl.load_workbook(path, data_only=True)
            wsv = wbv[ws.title]
            hidden = [i for i, d in wsv.row_dimensions.items() if d.hidden]
            if hidden:
                rep.warn(f"{len(hidden)} hidden row(s) in '{ws.title}' were read like any other row (first: row {min(hidden)})")
            merged = [str(r) for r in getattr(wsv, "merged_cells", []).ranges] if hasattr(wsv, "merged_cells") else []
            if merged:
                rep.warn(f"{len(merged)} merged cell range(s) in '{ws.title}' — only the top-left cell holds a value, "
                         "so a merged header spans columns that arrive blank")
        except Exception:
            pass
        # formulas whose cached value is missing read as None: say so instead of "no IP address"
        try:
            wbf = openpyxl.load_workbook(path, data_only=False, read_only=True)
            wsf = wbf[ws.title]
            nform = 0
            for ri, r in enumerate(wsf.iter_rows(values_only=True)):
                for ci, v in enumerate(r):
                    if isinstance(v, str) and v.startswith("=") and ri < len(rows) and ci < len(rows[ri]) and rows[ri][ci] is None:
                        rows[ri][ci] = "#FORMULA#"; nform += 1
            if nform:
                rep.warn(f"{nform} formula cell(s) had no calculated value (file never opened in Excel after editing) — "
                         "open it in Excel, save, and run again, or paste values")
        except Exception:
            pass
        return rows, ws.title
    if ext == ".xls":
        sys.exit("legacy .xls: open it in Excel and Save As .xlsx (or .csv) first, then run again")
    return _read_delimited(path, rep), os.path.basename(path)


def _read_delimited(path, rep=None):
    """CSV/TXT in whatever encoding and delimiter it turns up in."""
    csv.field_size_limit(min(2 ** 31 - 1, sys.maxsize))     # a huge single field must not raise _csv.Error
    data = open(path, "rb").read()
    enc = "utf-8-sig"
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        enc = "utf-16"
    else:
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            enc = "cp1252"
            if rep is not None:
                rep.warn("the file is not valid UTF-8; it was read as Windows-1252. If accented text looks wrong, "
                         "re-save it from Excel as 'CSV UTF-8'")
    text = open(path, "r", encoding=enc, errors="replace", newline="").read()
    # csv.Sniffer guesses from the whole sample and is thrown off by a title row above the header, and by one
    # ragged row. Parse with each candidate delimiter and keep whichever yields the most IPAM headers.
    best, best_score = None, (-1, -1)
    for delim in (",", ";", "\t", "|"):
        try:
            rows = [list(r) for r in csv.reader(text.splitlines(), delimiter=delim)]
        except csv.Error:
            continue
        hits = max((sum(1 for c in r if canonical_header(c)) for r in rows[:50]), default=0)
        width = max((len(r) for r in rows[:50]), default=0)
        if (hits, width) > best_score:
            best, best_score = rows, (hits, width)
    return best if best is not None else [list(r) for r in csv.reader(text.splitlines())]


def find_header(rows, rep: Report):
    """Header row = the row in the first 50 with the MOST recognised names (ties go to the earliest).

    Scoring the whole window instead of stopping at the first hit matters because a merged group-header row
    ("Network" | "Device") sits above the real header and used to win, which collapsed the whole file.
    """
    best, best_hits, best_cells = None, 0, 0
    for i, r in enumerate(rows[:50]):
        cells = [clean_text(c) for c in r]
        filled = sum(1 for c in cells if c)
        if not filled:
            continue
        hits = sum(1 for c in cells if canonical_header(c))
        if hits > best_hits or (hits == best_hits and hits > 0 and filled > best_cells + 1):
            best, best_hits, best_cells = i, hits, filled
    if best is None or best_hits == 0:
        return None, []
    # a single recognised name on a one-cell row is a title banner, not a header
    if best_hits == 1 and best_cells == 1:
        later = [(i, sum(1 for c in rows[i] if canonical_header(clean_text(c))))
                 for i in range(best + 1, min(len(rows), 50))]
        better = [i for i, h in later if h >= 1 and sum(1 for c in rows[i] if clean_text(c)) > 1]
        if better:
            best = better[0]
    if best > 0:
        rep.warn(f"header found on row {best + 1}; {best} title/blank row(s) above it were skipped")
    return best, [clean_text(c) for c in rows[best]]


# ----------------------------------------------------------------------------------------------------
# main transform
# ----------------------------------------------------------------------------------------------------
def fix(rows, rep: Report, mode: str, default_status: str, expand: bool, dedupe: str, strict: bool,
        avail_conflict: str = "flag", version: str = ""):
    hi, headers = find_header(rows, rep)
    if hi is None:
        sys.exit("no header row found — the first rows must contain names like 'IP Address' or 'Subnet Address'")
    # map headers
    canon_of = []
    custom_names = []
    seen = Counter()
    used_names = set()
    for idx, h in enumerate(headers):
        c = canonical_header(h) if h else None
        if c and seen[c]:
            # a second column with the same meaning must NOT be written back over the validated value
            alt = f"{h} ({seen[c] + 1})"
            rep.warn(f"duplicate column '{h}' maps to '{c}' again — kept separately as '{alt}'; the validated "
                     "value wins in the canonical column")
            c = None
            custom_names.append(alt); used_names.add(alt); canon_of.append(None); continue
        if c:
            seen[c] += 1
        canon_of.append(c)
        name = h
        if h and not c:
            if name in used_names or canonical_header(name):
                name = f"{h} ({idx + 1})"
            rep.warn(f"unknown column '{h}' kept as a custom property — it must exist in IPAM before import or the wizard will not map it")
        custom_names.append(name if not c else None)
        if name:
            used_names.add(name)
    have = {c for c in canon_of if c}
    sig = structure_score(headers)
    if mode == "auto":
        if "Subnet Address" in have and "IP Address" not in have:
            mode = "subnets"
        elif sig >= 2:
            mode = "subnets"
            rep.warn(f"IPAM structure export detected ({sig} structure-only columns) — read as a SUBNET import, "
                     "so 'Address' is the subnet network address and not a host address")
        elif "IP Address" in have:
            mode = "ips"
        elif "Subnet Address" in have:
            mode = "subnets"
        else:
            sys.exit(f"cannot tell IPs from subnets: recognised columns are {sorted(have)}; pass --mode")
    if mode == "subnets":
        # On a structure sheet these columns mean something else than on an IP sheet. Only remap when
        # the destination is not already present, so a sheet carrying both stays untouched.
        remap = {src: dst for src, dst in STRUCTURE_REMAP.items() if src in have and dst not in have}
        if remap:
            canon_of = [remap.get(c, c) for c in canon_of]
            have = {c for c in canon_of if c}
            for src, dst in remap.items():
                rep.warn(f"structure sheet: the '{src}' column is really {dst} here — mapped to {dst}")
    rep.warn(f"mode: {mode} import; recognised columns: {', '.join(sorted(have))}")

    out_rows = []
    blank_bools = set()
    data = rows[hi + 1:]
    for offset, r in enumerate(data):
        rownum = hi + 2 + offset                      # Excel 1-based row number
        cells = [clean_text(c) for c in r] + [""] * (len(headers) - len(r))
        if len(r) > len(headers) and any(clean_text(x) for x in r[len(headers):]):
            rep.fix(rownum, "(beyond last column)", " | ".join(clean_text(x) for x in r[len(headers):])[:120], "",
                    f"data past the last header column ({len(headers)}) ignored — add a header for it")
        cells = cells[:len(headers)]
        if not any(cells):
            continue
        rec = OrderedDict()
        custom = OrderedDict()
        for i, (h, c, v) in enumerate(zip(headers, canon_of, cells)):
            if c:
                rec[c] = cell_value(v, c, rownum, rep)
            elif h:
                custom[custom_names[i] or h] = cell_value(v, custom_names[i] or h, rownum, rep)
            elif v:
                # a blank header means the wizard has nothing to map; do not drop the data silently
                rep.fix(rownum, f"column {i + 1}", v[:60], "",
                        "dropped: this column has a blank header, so IPAM cannot map it — name the column to keep it")
        # record cleaning that changed text (raw list padded/truncated to the header width)
        raws = (list(r) + [None] * len(headers))[:len(headers)]
        for h, c, raw in zip(headers, canon_of, raws):
            if raw is not None and not isinstance(raw, (int, float, bool)) and clean_text(raw) != str(raw):
                rep.fix(rownum, c or h, raw, clean_text(raw), "text cleaned (spaces/hidden characters)")

        # Subnet Mask -> CIDR (both modes)
        if rec.get("Subnet Mask") and not rec.get("Subnet CIDR"):
            cidr = parse_cidr(rec["Subnet Mask"])
            if cidr is not None:
                rec["Subnet CIDR"] = str(cidr); rep.fix(rownum, "Subnet CIDR", rec["Subnet Mask"], cidr, "mask converted to CIDR")
        if rec.get("Subnet Mask"):
            _m = parse_cidr(rec["Subnet Mask"])
            if _m is None:
                rep.fix(rownum, "Subnet Mask", rec["Subnet Mask"], "", "mask is not a valid dotted mask — dropped, CIDR is used instead")
            elif rec.get("Subnet CIDR") and str(_m) != str(rec["Subnet CIDR"]):
                rep.fix(rownum, "Subnet Mask", rec["Subnet Mask"], f"/{rec['Subnet CIDR']}",
                        f"mask says /{_m} but CIDR says /{rec['Subnet CIDR']} — CIDR wins (IPAM treats CIDR as authoritative); check the source")
        rec.pop("Subnet Mask", None)
        # "192.0.2.0/24" written into Subnet Address
        sa = rec.get("Subnet Address", "")
        if sa and "/" in sa:
            addr, _, bits = sa.partition("/")
            rec["Subnet Address"] = addr.strip()
            if not rec.get("Subnet CIDR"):
                rec["Subnet CIDR"] = bits.strip()
            rep.fix(rownum, "Subnet Address", sa, rec["Subnet Address"], "subnet/CIDR split into two columns")
        if rec.get("Subnet CIDR"):
            _sa = rec.get("Subnet Address") or rec.get("IP Address") or ""
            _v = 6 if ":" in _sa else (4 if _sa else None)
            c = parse_cidr(rec["Subnet CIDR"], _v)
            if c is None:
                rep.reject(rownum, f"bad CIDR/mask {rec['Subnet CIDR']!r}", dict(rec), custom); continue
            if str(c) != rec["Subnet CIDR"]:
                rep.fix(rownum, "Subnet CIDR", rec["Subnet CIDR"], c, "CIDR normalised")
            rec["Subnet CIDR"] = str(c)
        if rec.get("Subnet Address"):
            ip, note = parse_ip(rec["Subnet Address"])
            if ip is None:
                rep.reject(rownum, f"bad subnet address: {note}", dict(rec), custom); continue
            if note:
                rep.fix(rownum, "Subnet Address", rec["Subnet Address"], ip, note)
            rec["Subnet Address"] = str(ip)
            if rec.get("Subnet CIDR"):
                net = ipaddress.ip_network(f"{ip}/{rec['Subnet CIDR']}", strict=False)
                if str(net.network_address) != str(ip):
                    rep.fix(rownum, "Subnet Address", ip, net.network_address, "host bits set — moved to the network address")
                    rec["Subnet Address"] = str(net.network_address)

        if mode == "subnets":
            if not rec.get("Subnet Address"):
                rep.reject(rownum, "no subnet address", dict(rec), custom); continue
            if not rec.get("Subnet CIDR"):
                rep.reject(rownum, "no CIDR / mask", dict(rec), custom); continue
            if rec.get("VLAN"):
                v = re.sub(r"[^\d]", "", rec["VLAN"])
                if v != rec["VLAN"]:
                    rep.fix(rownum, "VLAN", rec["VLAN"], v, "VLAN reduced to its number")
                rec["VLAN"] = v
            if not rec.get("Subnet Name"):
                rec["Subnet Name"] = f"{rec['Subnet Address']}/{rec['Subnet CIDR']}"
                rep.fix(rownum, "Subnet Name", "", rec["Subnet Name"], "subnet name filled from address")
            if "Type" in rec:
                t = clean_text(rec["Type"]); low = t.lower()
                canon = next((x for x in STRUCTURE_TYPES if x.lower() == low), None) or STRUCTURE_TYPE_SYNONYMS.get(low)
                if canon and canon != t:
                    rep.fix(rownum, "Type", t, canon, "structure Type spelled as IPAM writes it")
                    rec["Type"] = canon
                elif not canon:
                    rec["Type"] = "Subnet" if not t else t
                    rep.fix(rownum, "Type", t, rec["Type"],
                            f"Type {t!r} is not one of {'/'.join(STRUCTURE_TYPES)}" + (" -> Subnet" if not t else " — check it"))
            for b in ("Retain User Data", "Disable Auto Scanning", "Disable Neighbor Scanning"):
                if b in rec:
                    v = normalise_bool(rec[b])
                    if v is None:
                        # A blank here is the most common documented import error, but IPAM's own KB says to
                        # map the column to [Do not import] — inventing N where the operator meant Y would be a
                        # silent semantic change, so the blank is reported and left alone.
                        if clean_text(rec[b]):
                            rep.fix(rownum, b, rec[b], rec[b], f"{b} value is not Y/N — IPAM rejects it; fix it or map the column to [Do not import]")
                        else:
                            blank_bools.add(b)
                    else:
                        yn = {"Yes": "Y", "No": "N"}[v]
                        if yn != rec[b]:
                            rep.fix(rownum, b, rec[b], yn, f"{b} normalised to Y/N")
                        rec[b] = yn
            if int(rec["Subnet CIDR"]) < 20 and ":" not in rec["Subnet Address"]:
                rep.warn("a subnet larger than /20 is present: IPAM only displays addresses inside ranges you add explicitly "
                         "(4,096-address display threshold) — add IP ranges after the import or the subnet will look empty")
            rec["Comments"] = strip_markup(rec.get("Comments", ""), "Comments", rownum, rep)
            _cap(rec, "Comments", COMMENT_MAX, rownum, rep)
            for _k, _v in custom.items():
                rec.setdefault(_k, _v)
            out_rows.append((rownum, rec))
            continue

        # ---- IP rows ----
        ipcell = rec.get("IP Address", "")
        if not ipcell:
            rep.reject(rownum, "no IP address", dict(rec), custom); continue
        ips = None
        # "192.0.2.5/24" is a host address carrying its mask, NOT a request to enumerate the subnet.
        # Expanding it used to fabricate 254 rows that inherited this row's hostname (found 2026-09-03).
        _hip, _hbits = split_prefix(ipcell)
        if _hip is not None and _hbits is not None:
            _net = ipaddress.ip_network(f"{_hip}/{_hbits}", strict=False)
            _is_network = (int(_hip) == int(_net.network_address))
            _host_width = (_hbits == 32 and _hip.version == 4) or (_hbits == 128 and _hip.version == 6)
            if not _is_network or _host_width:
                ips = [_hip]
                if not _host_width:
                    if not rec.get("Subnet Address"):
                        rec["Subnet Address"], rec["Subnet CIDR"] = str(_net.network_address), str(_net.prefixlen)
                    rep.fix(rownum, "IP Address", ipcell, str(_hip),
                            f"host address carried its mask — kept as one host, /{_hbits} moved to the Subnet columns")
        if ips is None and "/" in ipcell and not ipcell.endswith(("/32", "/128")):
            # a subnet written in the IP column: "192.0.2.0/24" -> expand hosts (if enabled) or reject
            try:
                net = ipaddress.ip_network(ipcell.replace(" ", ""), strict=False)
                if net.num_addresses > RANGE_MAX:
                    rep.reject(rownum, f"subnet {ipcell} in the IP column is too large to expand ({net.num_addresses} addresses)", dict(rec)); continue
                if not expand:
                    rep.reject(rownum, f"subnet {ipcell} in the IP column (use --mode subnets or allow range expansion)", dict(rec)); continue
                ips = list(net.hosts()) or [net.network_address]
                rep.fix(rownum, "IP Address", ipcell, f"{len(ips)} host rows", "subnet in IP column expanded to hosts")
                if not rec.get("Subnet Address"):
                    rec["Subnet Address"], rec["Subnet CIDR"] = str(net.network_address), str(net.prefixlen)
            except ValueError:
                pass
        if ips is None:
            rng = expand_range(ipcell)
            if rng == "too-big":
                rep.reject(rownum, f"range {ipcell} exceeds {RANGE_MAX} addresses", dict(rec), custom); continue
            if rng:
                if not expand:
                    rep.reject(rownum, f"range {ipcell} (range expansion disabled)", dict(rec)); continue
                ips = rng; rep.fix(rownum, "IP Address", ipcell, f"{len(ips)} rows", "IP range expanded")
        if ips is None:
            ip, note = parse_ip(ipcell)
            if ip is None:
                rep.reject(rownum, note, dict(rec), custom); continue
            if note:
                rep.fix(rownum, "IP Address", ipcell, ip, note)
            ips = [ip]

        # shared field fixes
        has_data = any(clean_text(rec.get(c, "")) for c in ASSIGNED_EVIDENCE)
        st, note = normalise_status(rec.get("Status", ""), default_status, has_data)
        if note:
            rep.fix(rownum, "Status", rec.get("Status", ""), st, note)
        rec["Status"] = st
        if "Type" in rec and clean_text(rec["Type"]):
            t = clean_text(rec["Type"]); canon = next((x for x in ALLOC_POLICIES if x.lower() == t.lower()), None)
            if canon and canon != t:
                rep.fix(rownum, "Type", t, canon, "alloc policy spelled as the API writes it")
                rec["Type"] = canon
            elif not canon:
                rep.fix(rownum, "Type", t, t, f"Type {t!r} is not Static/Dynamic — left as is, map it to [Do not import] if the wizard rejects it")
        if "MAC Address" in rec:
            mac, note = normalise_mac(rec["MAC Address"])
            if note:
                rep.fix(rownum, "MAC Address", rec["MAC Address"], mac, note)
            rec["MAC Address"] = mac
        if rec.get("DNS"):
            d = rec["DNS"].rstrip(".").strip()
            if " " in d:
                d2 = re.sub(r"\s+", "-", d)
                rep.fix(rownum, "DNS", d, d2, "hostname had spaces — replaced with hyphens (check it)")
                d = d2
            elif d != rec["DNS"]:
                rep.fix(rownum, "DNS", rec["DNS"], d, "hostname trimmed")
            if len(d) > HOSTNAME_MAX:
                rep.fix(rownum, "DNS", f"{len(d)} chars", f"{HOSTNAME_MAX} chars", "hostname truncated (safety cap)")
            rec["DNS"] = d[:HOSTNAME_MAX]
        if "Skip Scan" in rec:
            b = normalise_bool(rec["Skip Scan"])
            if b is None:
                rep.fix(rownum, "Skip Scan", rec["Skip Scan"], "No", "unreadable Skip Scan value -> No"); b = "No"
            elif b != rec["Skip Scan"]:
                rep.fix(rownum, "Skip Scan", rec["Skip Scan"], b, "Skip Scan normalised")
            rec["Skip Scan"] = b
        rec["Comments"] = strip_markup(rec.get("Comments", ""), "Comments", rownum, rep)
        _cap(rec, "Comments", COMMENT_MAX, rownum, rep)
        _cap(rec, "Alias", ALIAS_MAX, rownum, rep)
        # IPAM's Available-must-be-empty rule (see AVAILABLE_MUST_BE_EMPTY): resolve the contradiction here
        # rather than letting the wizard redden the rows.
        if rec.get("Status") == "Available":
            carried = [c for c in AVAILABLE_MUST_BE_EMPTY if clean_text(rec.get(c, ""))]
            if carried:
                assigned = [c for c in carried if c in ASSIGNED_EVIDENCE]
                if avail_conflict == "promote" and assigned:
                    rec["Status"] = "Used"
                    rep.fix(rownum, "Status", "Available", "Used",
                            "Available row carried " + "/".join(carried) + " — IPAM requires those to be empty on an available address, so it is marked Used (--available-conflict clear blanks the fields instead)")
                elif avail_conflict == "promote":
                    # only a comment conflicts: neither losing the comment nor claiming the address is in use
                    # is safe, so keep both and say what IPAM may do about it
                    rep.fix(rownum, "Comments", rec.get("Comments", "")[:60], rec.get("Comments", "")[:60],
                            "Available row carries a comment — IPAM wants Comments empty on an available address and may flag it; "
                            "kept because dropping it would lose data (--available-conflict clear blanks it)")
                elif avail_conflict == "clear":
                    for c in carried:
                        rep.fix(rownum, c, rec[c][:60], "", "cleared: IPAM requires this to be empty when Status is Available")
                        rec[c] = ""
                else:
                    rep.fix(rownum, "Status", "Available", "Available",
                            "Available row carries " + "/".join(carried) + " — IPAM will likely redden these rows in validation (--available-conflict promote|clear resolves it)")
        for _k, _v in custom.items():
            rec.setdefault(_k, _v)
        for ip in ips:
            r2 = OrderedDict(rec); r2["IP Address"] = str(ip)
            if len(ips) > 1 and r2.get("MAC Address"):
                r2["MAC Address"] = ""          # one MAC cannot belong to a whole range
            out_rows.append((rownum, r2))

    # duplicates
    key = (lambda rec: rec.get("IP Address", "").lower()) if mode == "ips" else (lambda rec: f"{rec.get('Subnet Address','')}/{rec.get('Subnet CIDR','')}")
    seen_keys = {}
    seen_pos = {}
    final = []
    for rownum, rec in out_rows:
        k = key(rec)
        if k in seen_keys:
            first = seen_keys[k]
            if dedupe == "flag":
                rep.fix(rownum, "IP Address" if mode == "ips" else "Subnet Address", k, k, f"duplicate of row {first} (kept both — resolve by hand)")
                final.append((rownum, rec))
            elif dedupe == "keep-last":
                final[seen_pos[k]] = None            # O(1); the Nones are dropped below
                rep.fix(rownum, "IP Address" if mode == "ips" else "Subnet Address", k, k, f"duplicate: row {first} replaced by this row")
                seen_pos[k] = len(final)
                final.append((rownum, rec))
            else:
                rep.fix(rownum, "IP Address" if mode == "ips" else "Subnet Address", k, k, f"duplicate of row {first} dropped (kept first)")
            continue
        seen_keys[k] = rownum
        seen_pos[k] = len(final)
        final.append((rownum, rec))
    final = [x for x in final if x is not None]

    # Orphaned IPs: a row whose address is inside no subnet IPAM knows becomes an orphan and raises a
    # permanent warning banner on Manage Subnets & IP Addresses. Check against the subnets declared here.
    if mode == "ips":
        nets = set()
        for _, rec in final:
            if rec.get("Subnet Address") and rec.get("Subnet CIDR"):
                try:
                    nets.add(ipaddress.ip_network(f"{rec['Subnet Address']}/{rec['Subnet CIDR']}", strict=False))
                except ValueError:
                    pass
        if nets:
            orphans = [rn for rn, rec in final
                       if not any(ipaddress.ip_address(rec["IP Address"]) in n for n in nets
                                  if n.version == ipaddress.ip_address(rec["IP Address"]).version)]
            if orphans:
                rep.warn(f"{len(orphans)} address(es) fall outside every subnet named in this file (first at row {orphans[0]}) — "
                         "they import as orphans and IPAM shows a warning banner until you assign them a subnet")
        else:
            rep.warn("no Subnet Address/CIDR column: IPAM will place these addresses only if a matching subnet already exists, "
                     "otherwise they become orphans")

    for ver, text in VERSION_TRAPS:
        if ver == "all" or (version and version.startswith(ver.rstrip("x").rstrip("."))):
            rep.warn(text)
    if version:
        rep.warn(f"checked against the traps recorded for IPAM {version}; the column contract itself is identical "
                 "in the 2020.2.1 and 2026.2 Administrator Guides")

    # --strict is applied in main() AFTER the workbook is written, so the report it points at exists
    # column order: canonical first (in HEADER_ALIASES order), then custom properties
    order = (["IP Address", "Status", "Type", "Alias", "MAC Address", "DNS", "Comments", "Skip Scan",
              "Subnet Address", "Subnet CIDR", "Machine Type", "Vendor", "System Name", "System Description",
              "System Contact", "System Location", "DHCP Client Name"]
             if mode == "ips" else ["Type", "Subnet Address", "Subnet CIDR", "Subnet Name", "VLAN", "Location", "Group",
                                    "Comments", "Retain User Data", "Disable Auto Scanning", "Disable Neighbor Scanning"])
    mapped = {c for c in canon_of if c} | {c for _, rec in final for c in rec}
    cols = [c for c in order if c in mapped]
    extra = []
    for _, rec in final:
        for k in rec:
            if k not in cols and k not in extra:
                extra.append(k)
    for n in custom_names:
        if n and n not in cols and n not in extra:
            extra.append(n)
    if blank_bools:
        rep.warn("these columns are blank on some rows and IPAM rejects a blank boolean: "
                 + ", ".join(sorted(blank_bools)) + " — fill them with Y/N or map them to [Do not import] in the wizard")
    # the mapping the wizard will ask you to confirm
    rep.warn("column mapping — " + "; ".join(f"{h!r} -> {c}" for h, c in zip(headers, canon_of) if h and c)
             + ("; unmapped: " + ", ".join(repr(n) for n in custom_names if n) if any(custom_names) else ""))
    return mode, cols + extra, [rec for _, rec in final]


def _cap(rec, col, n, rownum, rep):
    if rec.get(col) and len(rec[col]) > n:
        rep.fix(rownum, col, f"{len(rec[col])} chars", f"{n} chars", f"{col} truncated to {n} characters")
        rec[col] = rec[col][:n]


# ----------------------------------------------------------------------------------------------------
# writing
# ----------------------------------------------------------------------------------------------------
ILLEGAL_XL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def _safe(v):
    """openpyxl refuses control characters — the Report shows raw 'before' values, so scrub on the way out."""
    if v is None:
        return ""
    if isinstance(v, (int, float, bool)):
        return v
    return ILLEGAL_XL.sub("\u2423", str(v))          # ␣ marks where a control character was


def write_outputs(out_path, cols, records, rep: Report, mode, csv_too: bool, inputs=()):
    import openpyxl
    from openpyxl.styles import Font, PatternFill
    from openpyxl.utils import get_column_letter
    wb = openpyxl.Workbook()
    ws = wb.active; ws.title = "Import"
    ws.append(cols)
    for rec in records:
        ws.append([_safe(rec.get(c, "")) for c in cols])
    for ci, c in enumerate(cols, 1):
        for cell in ws[get_column_letter(ci)]:
            cell.number_format = "@"                     # text: Excel must never re-interpret an IP or a MAC
        ws.column_dimensions[get_column_letter(ci)].width = max(12, min(40, max(len(str(r.get(c, ""))) for r in records[:500]) + 2 if records else 14))
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF"); cell.fill = PatternFill("solid", fgColor="2B579A")
    ws.freeze_panes = "A2"

    wr = wb.create_sheet("Rejected")
    wr.append(["Source row", "Reason"] + cols)
    for rownum, reason, orig in rep.rejects:
        wr.append([rownum, _safe(reason)] + [_safe(orig.get(c, "")) for c in cols])
    for cell in wr[1]:
        cell.font = Font(bold=True)

    wp = wb.create_sheet("Report")
    wp.append(["ipam_import_fix report", dt.datetime.now().strftime("%Y-%m-%d %H:%M")])
    wp.append(["mode", mode]); wp.append(["rows written", len(records)]); wp.append(["rows rejected", len(rep.rejects)])
    wp.append([])
    wp.append(["fix", "count"])
    for note, n in rep.fixes.most_common():
        wp.append([_safe(note), n])
    wp.append([])
    for w in rep.warnings:
        wp.append(["note", _safe(w)])
    wp.append([])
    wp.append(["Source row", "Column", "Before", "After", "What"])
    for row in rep.rows:
        wp.append([_safe(x) for x in row])
    if rep.detail_dropped:
        wp.append([f"… {rep.detail_dropped} more individual changes not listed (the counts above are complete)"])
    wb.save(out_path)
    if csv_too:
        cpath = safe_output(os.path.splitext(out_path)[0] + ".csv", inputs, "the CSV", explicit=True)
        with open(cpath, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh); w.writerow(cols)
            for rec in records:
                w.writerow([_safe(rec.get(c, "")) for c in cols])
        return cpath
    return None


def unique_path(p):
    if not os.path.exists(p):
        return p
    base, ext = os.path.splitext(p); i = 2
    while os.path.exists(f"{base}-{i}{ext}"):
        i += 1
    return f"{base}-{i}{ext}"


def safe_output(path, inputs, what, explicit=False):
    """The source spreadsheet is never written over — not by the workbook and not by --csv.
    (2026-09-03: `--csv` together with `-o input.csv` wrote the CSV straight over the input file.)
    A path the user named explicitly may replace an existing file; the auto-generated name is versioned."""
    real_in = {os.path.realpath(x) for x in inputs}
    out = path if explicit else unique_path(path)
    while os.path.realpath(out) in real_in:
        base, ext = os.path.splitext(out)
        out = unique_path(f"{base}-fixed{ext}")
        print(f"  note: {what} would have overwritten the INPUT file; wrote {os.path.basename(out)} instead")
    d = os.path.dirname(os.path.abspath(out)) or "."
    if not os.path.isdir(d):
        sys.exit(f"output directory does not exist: {d}")
    if not os.access(d, os.W_OK):
        sys.exit(f"output directory is not writable: {d}")
    return out


# ----------------------------------------------------------------------------------------------------
# Batch: a whole folder, and every data sheet inside each workbook
#
# 2026-09-03. Two gaps closed here. (1) The tool took one file at a time, so a folder of exports meant
# running it once per file. (2) It converted only ONE worksheet and left the rest out of the deliverable
# with nothing but a note - a workbook holding both an IP sheet and a Structure sheet silently lost the
# structure half. IPAM imports addresses and structure separately anyway, so one output per sheet is
# also the shape the wizard wants.
# ----------------------------------------------------------------------------------------------------
SPREADSHEET_EXT = (".xlsx", ".xlsm", ".xltx", ".xltm", ".csv", ".tsv", ".txt")
OUTPUT_MARK = "_ipam_fixed"


def is_our_output(name: str) -> bool:
    """True for a file this tool produced, so a re-run never fixes its own output."""
    stem = os.path.splitext(os.path.basename(name))[0]
    return OUTPUT_MARK in stem


def gather_inputs(path: str, recurse: bool):
    """One file, or every spreadsheet in a folder. Our own outputs, hidden files and
    Excel's ~$ lock files are skipped."""
    if os.path.isfile(path):
        return [path]
    if not os.path.isdir(path):
        sys.exit(f"not found: {path}")
    hits = []
    walker = os.walk(path) if recurse else [(path, [], sorted(os.listdir(path)))]
    for root, dirs, files in walker:
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for n in sorted(files):
            if n.startswith(".") or n.startswith("~$") or is_our_output(n):
                continue
            if os.path.splitext(n)[1].lower() in SPREADSHEET_EXT:
                hits.append(os.path.join(root, n))
    return hits


def data_sheets(path: str, want: str | None):
    """Worksheet names that carry a recognisable IPAM header. [None] means 'the file itself'
    (CSV/TSV, or a workbook we cannot open as one)."""
    if os.path.splitext(path)[1].lower() not in (".xlsx", ".xlsm", ".xltx", ".xltm"):
        return [None]
    try:
        import openpyxl
        wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
    except Exception:
        return [None]
    try:
        if want:
            return [want]
        # Our own three-sheet output: only Import holds data. Rejected carries the same
        # column names, so without this a re-run would "fix" the rejects back in.
        if {"Import", "Rejected", "Report"} <= set(wb.sheetnames):
            return ["Import"]
        found = []
        for n in wb.sheetnames:
            probe = [[c for c in r] for r in wb[n].iter_rows(max_row=50, values_only=True)]
            if any(canonical_header(clean_text(c)) for r in probe for c in r):
                found.append(n)
        return found or [None]
    finally:
        try:
            wb.close()
        except Exception:
            pass


def out_name_for(src: str, sheet, many_sheets: bool, out_dir: str | None):
    stem = os.path.splitext(os.path.basename(src))[0]
    if many_sheets and sheet:
        safe = re.sub(r"[^A-Za-z0-9._-]+", "-", str(sheet)).strip("-") or "sheet"
        stem = f"{stem}_{safe}"
    d = out_dir or os.path.dirname(os.path.abspath(src))
    return os.path.join(d, stem + OUTPUT_MARK + ".xlsx")


def process_one(src, sheet, want_out, a, many_sheets):
    """Fix one worksheet. Returns a summary dict; never raises for a bad input file."""
    rep = Report()
    try:
        rows, used_sheet = read_rows(src, sheet, rep)
        mode, cols, records = fix(rows, rep, a.mode, a.default_status, not a.no_expand_ranges,
                                  a.dedupe, a.strict, a.available_conflict, a.ipam_version)
    except SystemExit as exc:
        msg = str(exc)
        # a .txt/.csv in the folder that is simply not a spreadsheet is skipped, not failed -
        # otherwise a stray readme makes a whole good batch exit non-zero
        skip = ("no header row found" in msg or "has no recognisable header" in msg
                or "not a readable Excel file" in msg)
        return {"src": src, "sheet": sheet, "error": msg, "skipped": skip, "written": 0, "rejected": 0}
    except Exception as exc:
        return {"src": src, "sheet": sheet, "error": f"{exc.__class__.__name__}: {exc}",
                "written": 0, "rejected": 0}
    out = safe_output(want_out, [src], "the output",
                      explicit=bool(a.output) or not a.keep_versions)
    try:
        cpath = write_outputs(out, cols, records, rep, mode, a.csv, [src])
    except PermissionError as exc:
        return {"src": src, "sheet": sheet, "error": f"cannot write {os.path.basename(out)}: {exc}",
                "written": 0, "rejected": 0}
    return {"src": src, "sheet": used_sheet, "out": out, "csv": cpath, "mode": mode,
            "written": len(records), "rejected": len(rep.rejects), "rep": rep, "error": None}


def print_one(r, a, verbose):
    if r.get("error"):
        mark = "--" if r.get("skipped") else "!!"
        print(f"  {mark} {os.path.basename(r['src'])}"
              + (f" [{r['sheet']}]" if r.get("sheet") else "")
              + (": not a spreadsheet, skipped" if r.get("skipped") else f": {r['error']}"))
        return
    label = os.path.basename(r["src"]) + (f" [{r['sheet']}]" if r.get("sheet") else "")
    print(f"{label} -> {os.path.basename(r['out'])}")
    print(f"  mode: {r['mode']}   rows written: {r['written']}   rejected: {r['rejected']}")
    if not verbose:
        return
    rep = r["rep"]
    for note, n in rep.fixes.most_common():
        print(f"  {n:6d}  {note}")
    for w in rep.warnings:
        print(f"  note: {w}")
    if rep.rejects:
        print("  rejected rows (see the Rejected sheet):")
        for rownum, reason, _ in rep.rejects[:15]:
            print(f"    row {rownum}: {reason}")
        if len(rep.rejects) > 15:
            print(f"    … {len(rep.rejects) - 15} more")
    if r.get("csv"):
        print(f"  csv: {r['csv']}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Fix an Excel/CSV sheet - or a whole folder of them - for SolarWinds IPAM import.")
    ap.add_argument("input", help="a spreadsheet, or a FOLDER to fix every spreadsheet inside")
    ap.add_argument("-o", "--output", help="output .xlsx for a single sheet, or an output FOLDER in batch mode "
                                           "(default: beside each input as <name>_ipam_fixed.xlsx)")
    ap.add_argument("--mode", choices=["auto", "ips", "subnets"], default="auto")
    ap.add_argument("--sheet", help="worksheet name (default: every sheet that has a recognisable header)")
    ap.add_argument("--first-sheet-only", action="store_true",
                    help="convert only the first data sheet. The default converts EVERY data sheet, so a workbook "
                         "holding both addresses and a structure/subnet sheet yields one output per sheet - IPAM "
                         "imports those separately anyway")
    ap.add_argument("--recurse", action="store_true", help="in a folder, also descend into subfolders")
    ap.add_argument("--keep-versions", action="store_true",
                    help="keep older outputs by writing <name>_ipam_fixed-2.xlsx and so on. The default overwrites "
                         "this tool's own previous output so a folder re-run does not multiply files. The INPUT is "
                         "never written to either way")
    ap.add_argument("--default-status", default="Available", choices=STATUS_VALUES,
                    help="Status for a row with no status AND no assignment evidence (default Available; a row "
                         "carrying a hostname/alias/MAC/DHCP name becomes Used - a comment alone does not)")
    ap.add_argument("--available-conflict", choices=["flag", "promote", "clear"], default="flag",
                    help="IPAM requires Alias/MAC/hostname/comments to be EMPTY when Status is Available. "
                         "flag (default) only reports the clash - the rule is documented for IPAM's API but only "
                         "inferred for the import wizard, so an explicit status you set is never rewritten. "
                         "promote marks rows carrying assignment evidence Used and keeps the data (a comment alone "
                         "is not evidence, so those stay Available and are reported); clear keeps Available and "
                         "blanks the fields")
    ap.add_argument("--mac-format", choices=["colon", "hyphen"], default="colon",
                    help="AA:BB:CC:DD:EE:FF (template + API form, default) or AA-BB-CC-DD-EE-FF (the wizard's hint)")
    ap.add_argument("--comment-max", type=int, default=COMMENT_MAX,
                    help="safety cap on comment length; SolarWinds publishes no real limit, every truncation is reported")
    ap.add_argument("--ipam-version", default="", help="e.g. 2020.2, 4.6, 2026.1 - adds that version's traps to the report")
    ap.add_argument("--no-expand-ranges", action="store_true", help="reject 'a-b' ranges and subnets-in-IP-column instead of expanding them")
    ap.add_argument("--dedupe", choices=["keep-first", "keep-last", "flag"], default="keep-first")
    ap.add_argument("--csv", action="store_true", help="also write a CSV of each Import sheet")
    ap.add_argument("--strict", action="store_true", help="exit non-zero if any row is rejected")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)

    MAC_FORMAT[0] = a.mac_format
    globals()["COMMENT_MAX"] = a.comment_max

    inputs = gather_inputs(a.input, a.recurse)
    batch = os.path.isdir(a.input)
    if not inputs:
        sys.exit(f"no spreadsheets found in {a.input}"
                 + ("" if a.recurse else " (use --recurse to include subfolders)"))

    out_dir = None
    if batch and a.output:
        out_dir = a.output
        os.makedirs(out_dir, exist_ok=True)
    elif batch and not a.output:
        out_dir = None                      # beside each input
    if not batch and a.output and os.path.splitext(a.output)[1].lower() not in (".xlsx", ".xlsm"):
        a.output = os.path.splitext(a.output)[0] + ".xlsx"
        print(f"  note: the output is a workbook, so it is written as {os.path.basename(a.output)}")

    jobs = []
    for src in inputs:
        sheets = data_sheets(src, a.sheet)
        if a.first_sheet_only:
            sheets = sheets[:1]
        many = len(sheets) > 1
        for sh in sheets:
            want = a.output if (not batch and a.output and not many) else out_name_for(src, sh, many, out_dir)
            jobs.append((src, sh, want, many))

    if batch and not a.quiet:
        print(f"{len(inputs)} file(s), {len(jobs)} sheet(s) to fix in {os.path.abspath(a.input)}\n")

    results = []
    for src, sh, want, many in jobs:
        r = process_one(src, sh, want, a, many)
        results.append(r)
        if not a.quiet:
            print_one(r, a, verbose=not batch)
            if batch:
                print()

    ok = [r for r in results if not r.get("error")]
    skipped = [r for r in results if r.get("error") and r.get("skipped")]
    bad = [r for r in results if r.get("error") and not r.get("skipped")]
    total_rows = sum(r["written"] for r in ok)
    total_rej = sum(r["rejected"] for r in ok)

    if batch and not a.quiet:
        print("-" * 64)
        print(f"  sheets fixed : {len(ok)}/{len(jobs) - len(skipped)}")
        if skipped:
            print(f"  skipped      : {len(skipped)} (not spreadsheets: "
                  + ", ".join(os.path.basename(r["src"]) for r in skipped[:6])
                  + (" …" if len(skipped) > 6 else "") + ")")
        print(f"  rows written : {total_rows}")
        print(f"  rows rejected: {total_rej}")
        modes = Counter(r["mode"] for r in ok)
        if modes:
            print("  modes        : " + ", ".join(f"{m} x{n}" for m, n in modes.most_common()))
        if bad:
            print(f"  FAILED       : {len(bad)}")
            for r in bad:
                print(f"    {os.path.basename(r['src'])}"
                      + (f" [{r['sheet']}]" if r.get("sheet") else "") + f": {r['error']}")
        for r in ok:
            if r["written"] == 0:
                print(f"  WARNING: no rows survived in {os.path.basename(r['src'])}"
                      + (f" [{r['sheet']}]" if r.get("sheet") else "")
                      + f" - {r['rejected']} row(s) are in its Rejected sheet")
    elif not batch:
        for r in ok:
            if r["written"] == 0:
                print(f"  WARNING: no rows survived - nothing to import. "
                      f"{r['rejected']} row(s) are in the Rejected sheet with reasons.")

    if bad:
        return 3
    if a.strict and total_rej:
        print(f"--strict: {total_rej} row(s) rejected across {len(ok)} sheet(s); see the Rejected sheets",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
