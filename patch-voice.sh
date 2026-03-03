#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OS="$(uname -s)"

echo -e "${BOLD}${BLUE}Claude Voice Patcher${NC}"
echo "══════════════════════"

# ── Find claude binary ────────────────────────────────────────────────────────
CLAUDE_LINK=$(which claude 2>/dev/null) || {
    echo -e "${RED}✗ 'claude' not found in PATH${NC}"
    exit 1
}

CLAUDE_REAL=$(readlink "$CLAUDE_LINK" 2>/dev/null) || CLAUDE_REAL="$CLAUDE_LINK"
if [[ ! "$CLAUDE_REAL" = /* ]]; then
    CLAUDE_REAL="$(dirname "$CLAUDE_LINK")/$CLAUDE_REAL"
fi

# Don't patch an already-patched binary
if [[ "$CLAUDE_REAL" == *"-voice" ]]; then
    echo -e "${YELLOW}⚠ The current 'claude' symlink already points to a patched binary.${NC}"
    echo -e "  Resolve this first: ln -sf <original-binary> $CLAUDE_LINK"
    exit 1
fi

VERSION=$("$CLAUDE_REAL" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || VERSION="unknown"
PATCHED="${CLAUDE_REAL}-voice"

echo -e "  Binary : $CLAUDE_REAL"
echo -e "  Version: ${BOLD}$VERSION${NC}"
echo -e "  Output : $PATCHED"
echo ""

# ── Copy ──────────────────────────────────────────────────────────────────────
echo -n "  Copying ... "
cp "$CLAUDE_REAL" "$PATCHED"
echo -e "${GREEN}done${NC}"

# ── Patch (Python) ────────────────────────────────────────────────────────────
echo -n "  Patching... "
export PATCHED

RESULT=$(python3 << 'PYEOF'
import re, sys, os

dst = os.environ['PATCHED']
data = bytearray(open(dst, 'rb').read())

# Feature flag function: function X(){return Y("tengu_amber_quartz",!1)}
m = re.search(rb'function (\w+)\(\)\{return \w+\("tengu_amber_quartz",!1\)\}', data)
if not m:
    print("ERROR: feature flag function not found — this version may not support voice")
    sys.exit(1)

flag_fn   = m.group(1)
flag_full = m.group(0)
flag_short = b'function ' + flag_fn + b'(){return!0}'
flag_new   = flag_short + b' ' * (len(flag_full) - len(flag_short))

# Visibility gate: function X(){if(!Y())return!1;return FLAG_FN()}
pat = (rb'function (\w+)\(\)\{if\(!\w+\(\)\)return!1;return '
       + re.escape(flag_fn) + rb'\(\)\}')
m2 = re.search(pat, data)
if not m2:
    print("ERROR: visibility gate function not found")
    sys.exit(1)

gate_fn   = m2.group(1)
gate_full = m2.group(0)
gate_short = b'function ' + gate_fn + b'(){return!0}'
gate_new   = gate_short + b' ' * (len(gate_full) - len(gate_short))

def patch_all(buf, old, new):
    count, start = 0, 0
    while (idx := buf.find(old, start)) != -1:
        buf[idx:idx+len(old)] = new
        count += 1
        start = idx + 1
    return count

n1 = patch_all(data, flag_full, flag_new)
n2 = patch_all(data, gate_full, gate_new)

if n1 == 0 or n2 == 0:
    print(f"ERROR: no replacements made (flag×{n1} gate×{n2})")
    sys.exit(1)

open(dst, 'wb').write(data)
print(f"{flag_fn.decode()}()×{n1}  {gate_fn.decode()}()×{n2}")
PYEOF
) || { echo -e "${RED}✗ $RESULT${NC}"; rm -f "$PATCHED"; exit 1; }

echo -e "${GREEN}$RESULT${NC}"

# ── Sign (macOS only) ─────────────────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
    echo -n "  Signing ... "
    codesign -s - --force "$PATCHED" 2>/dev/null
    echo -e "${GREEN}done${NC}"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo -n "  Verifying... "
VER_CHECK=$("$PATCHED" --version 2>/dev/null) || {
    echo -e "${RED}✗ binary failed to start — patch may be incompatible${NC}"
    rm -f "$PATCHED"
    exit 1
}
echo -e "${GREEN}$VER_CHECK${NC}"
echo ""

# ── Ask what to do ────────────────────────────────────────────────────────────
echo -e "${BOLD}How do you want to use the patched binary?${NC}"
echo ""
echo "  1) Replace 'claude' symlink   — 'claude' uses voice-patched binary"
echo "     (undo: claude update)"
echo ""
echo "  2) Add 'claude-voice' symlink — keeps original 'claude', adds new command"
echo ""
echo "  3) Do nothing                 — binary is at $PATCHED"
echo ""
read -rp "  Choice [1/2/3]: " CHOICE
echo ""

case "$CHOICE" in
    1)
        OLD_TARGET=$(readlink "$CLAUDE_LINK" 2>/dev/null || echo "$CLAUDE_LINK")
        ln -sf "$PATCHED" "$CLAUDE_LINK"
        echo -e "${GREEN}✓ Symlink updated.${NC}"
        echo -e "  'claude' → $PATCHED"
        echo -e "  ${YELLOW}Note:${NC} 'claude update' will revert this."
        echo -e "  Restore manually: ln -sf $OLD_TARGET $CLAUDE_LINK"
        ;;

    2)
        # Create a stable symlink in the same dir as the claude link
        LINK_DIR="$(dirname "$CLAUDE_LINK")"
        VOICE_LINK="$LINK_DIR/claude-voice"
        ln -sf "$PATCHED" "$VOICE_LINK"
        echo -e "${GREEN}✓ Created symlink: $VOICE_LINK${NC}"
        echo -e "  → $PATCHED"
        echo -e "  Use: ${BOLD}claude-voice${NC}  (works in scripts too, no shell reload needed)"
        ;;

    3)
        echo -e "  Binary saved to: ${BOLD}$PATCHED${NC}"
        ;;

    *)
        echo -e "${YELLOW}  Invalid choice. Binary saved to: $PATCHED${NC}"
        ;;
esac

echo ""
if [[ "$OS" == "Darwin" ]]; then
    echo -e "${BOLD}Note:${NC} Ad-hoc signing only works on this Mac."
    echo "      Friends should run this script on their own machine."
fi
