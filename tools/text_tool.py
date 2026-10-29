#!/usr/bin/env python3
"""Maintenance tool for the Russian text table: data/text/ru.json plus one fragment per content area,
data/text/ru/*.json (docs/engine/CONTENT_PACKAGES.md). A key is defined in exactly one of those files.

Every player-visible string lives in the table. Content and code refer to it by key:
  * data/mirror/**/*.json   -> "label_key" and presentation "key" fields
  * data/conversations/*.dialogue -> speaker ids and line text that is itself a key
  * *.gd                    -> tr("some.key")

Commands
  check                 missing keys (error), unused keys (warning), empty values (error),
                        Russian prose anywhere outside the table (error)
  sort                  rewrite each table file in canonical group order (stable, diff friendly)
  export-csv FILE       key,text rows for spreadsheets / translators / bulk tools
  import-csv FILE       update the file that defines each key (unknown keys are refused)

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
FRAGMENTS = ROOT / "data" / "text" / "ru"
GROUP_ORDER = ["ui", "menu", "opt", "obj", "speaker", "line", "dlg", "toy"]
CYRILLIC = re.compile(r"[Ѐ-ӿ]")
KEY = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")


def table_files():
    """The root table first, then the fragments in name order."""
    return [TABLE] + (sorted(FRAGMENTS.glob("*.json")) if FRAGMENTS.is_dir() else [])


def load_file(path):
    def no_dupes(pairs):
        seen = collections.OrderedDict()
        for key, value in pairs:
            if key in seen:
                raise SystemExit(f"duplicate key in {path.relative_to(ROOT)}: {key}")
            seen[key] = value
        return seen
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_dupes)


def load_tables():
    """[(path, table)] for every table file. A content key defined in two files is refused."""
    out, owner = [], {}
    for path in table_files():
        table = load_file(path)
        for key in table:
            if key.startswith("_"):
                continue
            if key in owner:
                raise SystemExit(f"key {key} is defined in {owner[key].relative_to(ROOT)} and {path.relative_to(ROOT)}")
            owner[key] = path
        out.append((path, table))
    return out


def load_table():
    """The merged table (keys starting with _ are each file's notes and are dropped, except the root's)."""
    merged = collections.OrderedDict()
    for path, table in load_tables():
        for key, value in table.items():
            if key.startswith("_") and path != TABLE:
                continue
            merged[key] = value
    return merged


def save_file(path, table):
    path.write_text(json.dumps(table, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")


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
    # The painted room's toys (assets/painted/*/props.json): each reaction may carry a "say" key.
    for path in (ROOT / "assets" / "painted").rglob("props.json"):
        def walk_say(node, where=str(path.relative_to(ROOT))):
            if isinstance(node, dict):
                if isinstance(node.get("say"), str) and node["say"]:
                    refs[node["say"]].append(where)
                for v in node.values():
                    walk_say(v, where)
            elif isinstance(node, list):
                for item in node:
                    walk_say(item, where)
        walk_say(json.loads(path.read_text(encoding="utf-8")))
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
            source = path.read_text(encoding="utf-8")
            for match in re.finditer(r'\btr\("([^"]+)"\)', source):
                refs[match.group(1)].append(str(path.relative_to(ROOT)))
            # Keys are also passed around as plain literals (display_key = "obj.tomas", table rows).
            for match in re.finditer(r'"((?:%s)\.[a-z0-9_.]+)"' % "|".join(GROUP_ORDER), source):
                refs[match.group(1)].append(str(path.relative_to(ROOT)))
    return refs


def prose_outside_table():
    """Files other than the table that contain Cyrillic letters."""
    offenders = []
    for folder, pattern in (("game", "*.gd"), ("autoload", "*.gd"), ("render", "*.gd"), ("render", "*.gdshader"),
                            ("data", "*.json"), ("data", "*.dialogue"), ("tests", "*.gd"), ("game", "*.tscn")):
        for path in (ROOT / folder).rglob(pattern):
            if path == TABLE or path.parent == FRAGMENTS:
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
        errors.append(f"Russian text outside the text table: {path}")
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
    total = 0
    for path, table in load_tables():
        about = {k: v for k, v in table.items() if k.startswith("_")}
        content = {k: v for k, v in table.items() if not k.startswith("_")}
        ordered = collections.OrderedDict(about)
        for key in sorted(content, key=sort_key):
            ordered[key] = content[key]
        save_file(path, ordered)
        total += len(content)
    print(f"sorted {total} strings")
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
    tables = load_tables()
    owner = {key: table for _, table in tables for key in table if not key.startswith("_")}
    updated, unknown = 0, []
    with open(path, encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            key, text = row["key"], row["text"]
            if key not in owner:
                unknown.append(key)
            elif owner[key][key] != text:
                owner[key][key] = text
                updated += 1
    if unknown:
        for key in unknown:
            print("ERROR   unknown key", key)
        return 1
    for file_path, table in tables:
        save_file(file_path, table)
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
