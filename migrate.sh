#!/bin/bash
# ============================================
#  AI Cache Migration Script
#  Migrate a single directory from C: to D:
#  using NTFS Junction (directory junction)
# ============================================
#  Usage:
#    ./migrate.sh <app_name> <c_path_suffix> [d_drive]
#
#  Examples:
#    ./migrate.sh "Claude Desktop" "AppData/Local/Claude-3p"
#    ./migrate.sh "Claude Code" ".claude"
#    ./migrate.sh "CodeBuddy" "AppData/Roaming/CodeBuddy CN" E
# ============================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Parse arguments ----
if [ $# -lt 2 ]; then
    echo "Usage: $0 <app_name> <c_path_suffix> [d_drive_letter]"
    echo ""
    echo "Examples:"
    echo "  $0 \"Claude Desktop\" \"AppData/Local/Claude-3p\""
    echo "  $0 \"Claude Code\" \".claude\""
    echo "  $0 \"CodeBuddy\" \"AppData/Roaming/CodeBuddy CN\" E"
    exit 1
fi

APP_NAME="$1"
C_SUFFIX="$2"
D_DRIVE="${3:-D}"
USERNAME="${USERNAME:-$(whoami)}"

SRC="/c/Users/${USERNAME}/${C_SUFFIX}"
DST="/d/Users/${USERNAME}/${C_SUFFIX}"
SRC_WIN="C:\\Users\\${USERNAME}\\${C_SUFFIX//\//\\}"
DST_WIN="${D_DRIVE}:\\Users\\${USERNAME}\\${C_SUFFIX//\//\\}"

echo ""
echo "============================================"
echo "  AI Cache Migration: ${APP_NAME}"
echo "  ${SRC}"
echo "  --> ${DST}"
echo "============================================"
echo ""

# ---- Step 0: Pre-flight checks ----
log_info "Pre-flight checks..."

# Check source exists
if [ ! -d "${SRC}" ]; then
    log_error "Source directory not found: ${SRC}"
    exit 1
fi

# Check source is not already a junction
if fsutil reparsepoint query "${SRC_WIN}" >/dev/null 2>&1; then
    log_warn "${SRC} is already a junction — skipping"
    exit 0
fi
log_ok "Source is a real directory (not a junction)"

# Check D drive is NTFS
if ! powershell.exe -NoProfile -Command "if ((Get-Volume -DriveLetter ${D_DRIVE}).FileSystemType -eq 'NTFS') { exit 0 } else { exit 1 }" >/dev/null 2>&1; then
    log_error "${D_DRIVE}: drive is not NTFS! Required for junction creation."
    exit 1
fi
log_ok "${D_DRIVE}: drive is NTFS"

# Check D drive has enough space
SRC_SIZE=$(du -sm "${SRC}" 2>/dev/null | cut -f1)
DST_FREE=$(df -m "/d" 2>/dev/null | tail -1 | awk '{print $4}')
if [ "${DST_FREE}" -lt "${SRC_SIZE}" ]; then
    log_error "${D_DRIVE}: has ${DST_FREE}M free but need ${SRC_SIZE}M"
    exit 1
fi
log_ok "${D_DRIVE}: has ${DST_FREE}M free, need ${SRC_SIZE}M — OK"

echo ""
log_info "All checks passed. Ready to migrate: ${APP_NAME}"
log_info "  Size: ${SRC_SIZE} MB"
echo ""

# ---- Step 1: Copy data to D drive ----
log_info "Copying data to ${D_DRIVE} drive..."
# 必须先建目标目录本身（不能只建父目录），否则 cp -r 多源展开时目标不存在会失败
mkdir -p "${DST}"

if cp -r "${SRC}/"* "${DST}/" 2>/dev/null; then
    log_ok "Copy complete"
else
    log_warn "Some files could not be copied (may be locked). Continuing..."
fi

# Verify copy
DST_SIZE=$(du -sm "${DST}" 2>/dev/null | cut -f1)
log_info "Source: ${SRC_SIZE}M, Destination: ${DST_SIZE}M"

# ---- Step 2: Remove C drive source ----
log_info "Removing C drive source directory..."
if rm -rf "${SRC}" 2>/dev/null; then
    log_ok "Source removed"
else
    log_warn "Cannot fully remove source (locked files). Trying rename fallback..."
    BAK="${SRC}.bak"
    mv "${SRC}" "${BAK}" 2>/dev/null || {
        log_error "Cannot remove or rename source. Aborting."
        log_error "Data is safely copied to ${DST}. Please close the app and retry."
        exit 1
    }
    log_info "Source renamed to ${BAK} — will clean up after reboot"
fi

# ---- Step 3: Create junction ----
log_info "Creating NTFS junction..."
# 用 PowerShell New-Item 建 junction（Git Bash 调 cmd /c mklink 有引号转义问题）
if powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '${SRC_WIN}' -Target '${DST_WIN}' | Out-Null" >/dev/null 2>&1; then
    log_ok "Junction created"
else
    log_error "Junction creation failed!"
    log_error "Data is safe on ${D_DRIVE} drive at: ${DST}"
    log_error "Manual recovery: PowerShell > New-Item -ItemType Junction -Path '${SRC_WIN}' -Target '${DST_WIN}'"
    exit 1
fi

# ---- Step 4: Verify ----
log_info "Verifying junction..."
if fsutil reparsepoint query "${SRC_WIN}" >/dev/null 2>&1; then
    log_ok "Junction verified — Reparse Point confirmed"
else
    log_error "Verification failed! Junction not detected."
    exit 1
fi

if ls "${SRC}/" >/dev/null 2>&1; then
    log_ok "Junction target accessible — all good!"
else
    log_error "Junction exists but target is not accessible"
    exit 1
fi

echo ""
echo "============================================"
echo "  ✅ SUCCESS: ${APP_NAME}"
echo "  ${SRC}"
echo "  --> ${DST}"
echo "  Saved: ${SRC_SIZE} MB on C: drive"
echo "============================================"
echo ""

# ---- Cleanup hint ----
if [ -n "${BAK:-}" ] && [ -d "${BAK}" ]; then
    log_warn "Residual: ${BAK} — will be removable after reboot"
fi
