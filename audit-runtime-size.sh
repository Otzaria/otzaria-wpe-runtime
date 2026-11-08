#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?usage: audit-runtime-size.sh <extracted-sdk-root>}"
[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
rows="$tmp/rows.tsv"
: > "$rows"

while IFS= read -r -d '' file; do
  if ! readelf -h "$file" >/dev/null 2>&1; then
    continue
  fi
  rel="${file#"$ROOT"/}"
  before="$(stat -c%s "$file")"
  copy="$tmp/elf"
  cp "$file" "$copy"
  # A failed strip is a broken measurement, not a zero-byte saving.
  if ! strip --strip-unneeded "$copy" >/dev/null 2>&1; then
    echo "strip failed for $rel" >&2
    exit 3
  fi
  after="$(stat -c%s "$copy")"
  savings=$((before - after))
  printf '%s\t%s\t%s\t%s\n' "$before" "$after" "$savings" "$rel" >> "$rows"
done < <(find "$ROOT" -type f -print0)

python3 - "$rows" <<'PY'
from pathlib import Path
import sys

rows = []
for line in Path(sys.argv[1]).read_text().splitlines():
    before, after, savings, path = line.split("\t", 3)
    rows.append((int(before), int(after), int(savings), path))

rows.sort(key=lambda r: (-r[2], r[3]))
total_before = sum(r[0] for r in rows)
total_after = sum(r[1] for r in rows)
total_savings = total_before - total_after

print(f"elf_count\t{len(rows)}")
print(f"elf_bytes_before\t{total_before}")
print(f"elf_bytes_after_strip_unneeded\t{total_after}")
print(f"potential_savings_bytes\t{total_savings}")
print(f"potential_savings_percent\t{(100*total_savings/total_before if total_before else 0):.2f}")
print()
print("before_bytes\tafter_bytes\tsavings_bytes\tpath")
for row in rows[:40]:
    print("\t".join(map(str, row)))
PY
