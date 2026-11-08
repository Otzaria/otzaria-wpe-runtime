#!/usr/bin/env bash
# Independent QA: published-size audit must not alter SDK source or mask failures.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk/lib" "$tmp/fake-bin"
cat > "$tmp/lib.c" <<'C'
#include <stdio.h>
void wpe_qa_export(void) { puts("audit"); }
C
cc -shared -fPIC -g -o "$tmp/sdk/lib/libWPEWebKit-2.0.so.1.5.12" "$tmp/lib.c"
sha="$(sha256sum "$tmp/sdk/lib/libWPEWebKit-2.0.so.1.5.12" | cut -d' ' -f1)"
bash "$repo/audit-runtime-size.sh" "$tmp/sdk" > "$tmp/actual.tsv"
grep -q '^elf_count[[:space:]]*1$' "$tmp/actual.tsv"
before="$(awk -F '\t' '$1=="elf_bytes_before"{print $2}' "$tmp/actual.tsv")"
after="$(awk -F '\t' '$1=="elf_bytes_after_strip_unneeded"{print $2}' "$tmp/actual.tsv")"
test "$before" -gt "$after"
test "$(sha256sum "$tmp/sdk/lib/libWPEWebKit-2.0.so.1.5.12" | cut -d' ' -f1)" = "$sha"
printf '#!/bin/sh\nexit 41\n' > "$tmp/fake-bin/strip"
chmod +x "$tmp/fake-bin/strip"
if PATH="$tmp/fake-bin:$PATH" bash "$repo/audit-runtime-size.sh" "$tmp/sdk" >"$tmp/out" 2>&1; then
  echo 'audit incorrectly reported success when strip failed' >&2; exit 1
fi
grep -q 'strip failed for lib/libWPEWebKit' "$tmp/out"
echo 'WPE SDK audit independent fixtures passed'
