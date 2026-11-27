#!/usr/bin/env python3
"""Check that every on-screen string has a Japanese and Chinese translation.

Strings are written where they are used as L("한국어", "English"). The English
literal is the key into Sources/PolyMacL10n/Catalog+<lang>.swift. An
interpolation \\(...) in the English literal becomes {0}, {1}, ... in the key,
in order, the same way LString builds the key at run time.

  scripts/check-l10n.py            fail if a key is missing or unused
  scripts/check-l10n.py --missing  print missing keys as Swift dictionary lines
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
L10N = SOURCES / "PolyMacL10n"
LANGS = ["ja", "zhHans", "zhHant"]


def read_literal(src, i):
    """src[i] is the opening quote. Returns (template, end) with interpolations
    replaced by {n}, escapes kept as written. end is the index after the quote."""
    assert src[i] == '"'
    if src.startswith('"""', i):
        raise ValueError("multi-line literal")
    i += 1
    out, n = [], 0
    while True:
        c = src[i]
        if c == '"':
            return "".join(out), i + 1
        if c == "\n":
            raise ValueError("unterminated literal")
        if c == "\\" and src[i + 1] == "(":
            depth, j = 1, i + 2
            while depth:
                if src[j] == '"':
                    _, j = read_literal(src, j)
                    continue
                if src[j] == "(":
                    depth += 1
                elif src[j] == ")":
                    depth -= 1
                j += 1
            out.append("{%d}" % n)
            n += 1
            i = j
            continue
        if c == "\\":
            out.append(src[i : i + 2])
            i += 2
            continue
        out.append(c)
        i += 1


def skip_space(src, i):
    while src[i] in " \t\n":
        i += 1
    return i


# L("…", "…") and module names ModuleDescriptor(displayName: ("…", "…"), summary: ("…", "…"))
CALL = re.compile(r'(?:(?<![\w.])L\(|\b(?:displayName|summary):\s*\()\s*"')


def used_keys():
    keys, problems = {}, []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.parent == L10N:
            continue
        src = path.read_text()
        for m in CALL.finditer(src):
            if "//" in src[src.rfind("\n", 0, m.start()) + 1 : m.start()]:
                continue  # in a comment
            line = src.count("\n", 0, m.start()) + 1
            where = f"{path.relative_to(ROOT)}:{line}"
            try:
                _, i = read_literal(src, m.end() - 1)
                i = skip_space(src, i)
                if src[i] != ",":
                    raise ValueError("expected a second argument")
                i = skip_space(src, i + 1)
                if src[i] != '"':
                    raise ValueError("English argument is not a literal")
                en, _ = read_literal(src, i)
            except (ValueError, IndexError) as e:
                problems.append(f"{where}: {e}")
                continue
            keys.setdefault(en, where)
    return keys, problems


ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)",?\s*$')


def catalog(lang):
    path = L10N / f"Catalog+{lang}.swift"
    entries = {}
    if path.exists():
        for line in path.read_text().splitlines():
            m = ENTRY.match(line)
            if m:
                entries[m.group(1)] = m.group(2)
    return entries


def placeholders(s):
    return set(re.findall(r"\{\d+\}", s))


def main():
    keys, problems = used_keys()
    if "--missing" in sys.argv:
        for lang in LANGS:
            have = catalog(lang)
            missing = [k for k in keys if k not in have]
            print(f"// {lang}: {len(missing)} missing")
            for k in missing:
                print(f'    "{k}": "",')
        return 0
    fail = bool(problems)
    for p in problems:
        print(f"✗ {p}", file=sys.stderr)
    for lang in LANGS:
        have = catalog(lang)
        for k, where in keys.items():
            if k not in have:
                print(f"✗ {lang}: no translation for \"{k}\" ({where})", file=sys.stderr)
                fail = True
            elif not have[k].strip():
                print(f"✗ {lang}: empty translation for \"{k}\"", file=sys.stderr)
                fail = True
            elif not placeholders(have[k]) <= placeholders(k):
                print(f"✗ {lang}: \"{have[k]}\" uses a placeholder that \"{k}\" does not have", file=sys.stderr)
                fail = True
        for k in have:
            if k not in keys:
                print(f"✗ {lang}: unused translation \"{k}\"", file=sys.stderr)
                fail = True
    if fail:
        print("  Add translations to Sources/PolyMacL10n/Catalog+<lang>.swift (scripts/check-l10n.py --missing)", file=sys.stderr)
        return 1
    print(f"✓ {len(keys)} strings translated ({', '.join(LANGS)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
