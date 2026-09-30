#!/usr/bin/env python3
"""Maintenance tool for the single Russian text table, data/text/ru.json.

Every player-visible string lives in that one file. Content and code refer to it by key:
  * data/mirror/**/*.json   -> "label_key" and presentation "key" fields
  * data/conversations/*.dialogue -> speaker ids and line text that is itself a key
  * *.gd                    -> tr("some.key")

Commands
  check                 missing keys (error), unused keys (warning), empty values (error),
                        Russian prose anywhere outside the table (error)
  sort                  rewrite ru.json in canonical group order (stable, diff friendly)
  export-csv FILE       key,text rows for spreadsheets / translators / bulk tools
  import-csv FILE       update ru.json from such a file (unknown keys are refused)

No third-party dependencies. Run from anywhere: paths resolve relative to the repo root.
"""
import csv
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "data" / "text" / "ru.json"
GROUP_ORDER = ["ui", "opt", "obj", "speaker", "line", "dlg"]
CYRILLIC = re.compile(r"[Ѐ-ӿ]")
KEY = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")


def load_table():
    def no_dupes(pairs):
        seen = collections.OrderedDict()
        for key, value in pairs:
            if key in seen:
                raise SystemExit(f"duplicate key in {TABLE.name}: {key}")
            seen[key] = value
        return seen
    return json.loads(TABLE.read_text(encoding="utf-8"), object_pairs_hook=no_dupes)


def save_table(table):
    TABLE.write_text(json.dumps(table, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")


def referenced_keys():
    """Returns {key: [where, ...]} for every key the project refers to."""
    refs = collections.defaultdict(list)

    def walk(node, where):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("label_key", "key") and isinstance(v, str):
                    refs[v].append(where)
                walk(v, where)
        elif isinstance(node, list):
            for item in node:
                walk(item, where)

    for path in (ROOT / "data" / "mirror").rglob("*.json"):
        walk(json.loads(path.read_text(encoding="utf-8")), str(path.relative_to(ROOT)))
    for path in (ROOT / "data" / "conversations").glob("*.dialogue"):
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            match = re.match(r"^(?:([a-z_][a-z0-9_]*):\s+)?([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)$", stripped)
            if match:
                refs[match.group(2)].append(str(path.relative_to(ROOT)))
            speaker = re.match(r"^([a-z_][a-z0-9_]*):\s+", stripped)
            if speaker and not stripped.startswith("~"):
                refs["speaker." + speaker.group(1)].append(str(path.relative_to(ROOT)))
    for folder in ("game", "autoload"):
        for path in (ROOT / folder).rglob("*.gd"):
            for match in re.finditer(r'\btr\("([^"]+)"\)', path.read_text(encoding="utf-8")):
                refs[match.group(1)].append(str(path.relative_to(ROOT)))
    return refs


def prose_outside_table():
    """Files other than the table that contain Cyrillic letters."""
    offenders = []
    for folder, pattern in (("game", "*.gd"), ("autoload", "*.gd"), ("render", "*.gd"), ("render", "*.gdshader"),
                            ("data", "*.json"), ("data", "*.dialogue"), ("tests", "*.gd"), ("game", "*.tscn")):
        for path in (ROOT / folder).rglob(pattern):
            if path == TABLE:
                continue
            if CYRILLIC.search(path.read_text(encoding="utf-8")):
                offenders.append(str(path.relative_to(ROOT)))
    return sorted(set(offenders))


def cmd_check():
    table = load_table()
    content = {k: v for k, v in table.items() if not k.startswith("_")}
    refs = referenced_keys()
    errors, warnings = [], []
    for key, places in sorted(refs.items()):
        if key not in content:
            errors.append(f"missing key '{key}' (used in {sorted(set(places))[0]})")
    for key, value in content.items():
        if not KEY.match(key):
            errors.append(f"malformed key '{key}' (expected group.name[.part], lowercase)")
        if not isinstance(value, str) or not value.strip():
            errors.append(f"empty text for '{key}'")
        elif not CYRILLIC.search(value) and value.strip(". ") != "":
            warnings.append(f"no Russian letters in '{key}': {value!r}")
        if key not in refs:
            warnings.append(f"unused key '{key}'")
    for path in prose_outside_table():
        errors.append(f"Russian text outside {TABLE.name}: {path}")
    for line in errors:
        print("ERROR  ", line)
    for line in warnings:
        print("warning", line)
    print(f"{len(content)} strings, {len(refs)} referenced keys, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


def sort_key(key):
    group = key.split(".", 1)[0]
    return (GROUP_ORDER.index(group) if group in GROUP_ORDER else len(GROUP_ORDER), key)


def cmd_sort():
    table = load_table()
    about = {k: v for k, v in table.items() if k.startswith("_")}
    content = {k: v for k, v in table.items() if not k.startswith("_")}
    ordered = collections.OrderedDict(about)
    for key in sorted(content, key=sort_key):
        ordered[key] = content[key]
    save_table(ordered)
    print(f"sorted {len(content)} strings")
    return 0


def cmd_export(path):
    table = load_table()
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["key", "text"])
        for key, value in table.items():
            if not key.startswith("_"):
                writer.writerow([key, value])
    print(f"wrote {path}")
    return 0


def cmd_import(path):
    table = load_table()
    updated, unknown = 0, []
    with open(path, encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            key, text = row["key"], row["text"]
            if key not in table:
                unknown.append(key)
            elif table[key] != text:
                table[key] = text
                updated += 1
    if unknown:
        for key in unknown:
            print("ERROR   unknown key", key)
        return 1
    save_table(table)
    print(f"updated {updated} strings")
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "check":
        return cmd_check()
    if len(argv) >= 2 and argv[1] == "sort":
        return cmd_sort()
    if len(argv) == 3 and argv[1] == "export-csv":
        return cmd_export(argv[2])
    if len(argv) == 3 and argv[1] == "import-csv":
        return cmd_import(argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
