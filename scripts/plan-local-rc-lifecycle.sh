#!/bin/bash
# Print a local RC lifecycle plan. This command never modifies the host.
set -euo pipefail

if [ "${1:-}" != "--plan" ]; then
  echo "usage: $0 --plan <install|upgrade|uninstall> [destination]" >&2
  exit 2
fi
ACTION="${2:-}"
DESTINATION="${3:-$HOME/Applications/DeskTidy.app}"
if [ -n "${4:-}" ]; then
  echo "usage: $0 --plan <install|upgrade|uninstall> [destination]" >&2
  exit 2
fi

canonical_path() {
  /usr/bin/python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

TARGET="$(canonical_path "$DESTINATION")"
DESKTOP="$(canonical_path "$HOME/Desktop")"
case "$TARGET" in
  "$DESKTOP"|"$DESKTOP"/*)
    echo "plan: refusing Desktop destination" >&2
    exit 2
    ;;
esac

case "$ACTION" in
  install)
    cat <<EOF
PLAN ONLY — no filesystem, service, login-item, or Desktop changes are made.
1. Run scripts/verify-local-rc.sh against the local RC archive and sidecar manifest.
2. Extract the verified archive into a fresh sibling staging directory.
3. Confirm the destination does not already contain DeskTidy.app.
4. Atomically move the staged DeskTidy.app to: $TARGET
5. Do not launch the app or register any service; inspect it manually only in this local RC lane.
EOF
    ;;
  upgrade)
    cat <<EOF
PLAN ONLY — no filesystem, service, login-item, or Desktop changes are made.
1. Run scripts/verify-local-rc.sh against the replacement local RC archive and sidecar manifest.
2. Extract the verified archive into a fresh sibling staging directory.
3. Preserve the existing destination until the replacement is fully verified.
4. Atomically replace: $TARGET
5. Do not launch the app or register any service; retain the previous app until human acceptance.
EOF
    ;;
  uninstall)
    cat <<EOF
PLAN ONLY — no filesystem, service, login-item, or Desktop changes are made.
1. Confirm the destination is the intended local RC app: $TARGET
2. Confirm no service registration or login item was created by this RC process.
3. Remove only the selected DeskTidy.app bundle after human approval.
4. Do not delete receipts, configuration, launch agents, or unrelated files.
EOF
    ;;
  *)
    echo "plan: action must be install, upgrade, or uninstall" >&2
    exit 2
    ;;
esac
