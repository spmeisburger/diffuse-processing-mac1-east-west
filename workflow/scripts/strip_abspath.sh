#!/usr/bin/env bash
set -euo pipefail
f="$1"
sed "s|$PWD/||g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"