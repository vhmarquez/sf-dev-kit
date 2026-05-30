#!/usr/bin/env bash
# Run the argo hook test suite locally. Requires bats-core (no CI by design).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  {
    echo "bats not found. Install it:"
    echo "  macOS:  brew install bats-core"
    echo "  npm:    npm install -g bats"
    echo "  apt:    sudo apt-get install bats"
  } >&2
  exit 127
fi

# The fake `sf` must be executable even if the checkout dropped the bit.
chmod +x "$ROOT/tests/helpers/sf" 2>/dev/null || true

exec bats "$ROOT/tests/"
