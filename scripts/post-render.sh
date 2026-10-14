#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p figures/release _book/output/figures

for figure in 1 2 3 4 5; do
  for ext in png pdf pptx; do
    source_file=""
    for suffix in combine composite; do
      candidate="output/figures/fig${figure}-${suffix}.${ext}"
      if [[ -f "$candidate" ]]; then
        source_file="$candidate"
        break
      fi
    done
    if [[ -n "$source_file" ]]; then
      cp "$source_file" "figures/release/Figure${figure}.${ext}"
    fi
  done
done

if [[ -d output/figures ]]; then
  cp -a output/figures/. _book/output/figures/
fi
