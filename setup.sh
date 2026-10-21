#!/usr/bin/env bash
# Atom Shell interactive setup wizard
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec "$ROOT/install.sh" "$@"
