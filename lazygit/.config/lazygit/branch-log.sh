#!/usr/bin/env bash
set -euo pipefail

git log \
  --graph \
  --color=always \
  --abbrev-commit \
  --decorate \
  --oneline | \
  sed -E \
    -e 's/\*//g' \
    -e 's/\///g' \
    -e 's/\\//g' \
    -e 's/\|/│/g'
