#!/bin/bash
# apt_source_repair.sh — fix broken APT sources on Ubuntu 20.04 / 22.04 / 24.04
#
# Usage:
#   sudo bash apt_source_repair.sh              # repair + backup
#   sudo bash apt_source_repair.sh --check      # dry-run: show what would change
#   sudo bash apt_source_repair.sh --restore    # restore from backup
#   sudo bash apt_source_repair.sh --mirror tw  # use Taiwan mirror (twaren)

set -euo pipefail

LOG_FILE="/var/log/apt_source_repair.log"
BACKUP_DIR="/etc/apt/backup/$(date +%Y%m%d_%H%M%S)"
SOURCES_LIST="/etc/apt/sources.list"
SOURCES_LIST_D="/etc/apt/sources.list.d"
DRY_RUN=false
MIRROR=""

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "ℹ️  $*"; }
ok()   { log "✅ $*"; }
warn() { log "⚠️  $*"; }
die()  { log "❌ $*"; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check|--dry-run) DRY_RUN=true ;;
      --restore)         do_restore; exit 0 ;;
      --mirror)          MIRROR="${2:-}"; shift ;;
      -h|--help)
        echo "Usage: $0 [--check] [--restore] [--mirror tw|default]"
        exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

require_root() {
  [ "$EUID" -eq 0 ] || die "Run as root: sudo bash $0"
}

detect_ubuntu() {
  UBUNTU_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
  UBUNTU_VERSION=$(. /etc/os-release && echo "${VERSION_ID:-}")
  [ -n "$UBUNTU_CODENAME" ] || die "Cannot detect Ubuntu codename"
  info "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

  # Ubuntu 24.04+ uses DEB822 format — sources.list is empty/unused
  if [[ "$UBUNTU_VERSION" == 24* ]] || [[ "$UBUNTU_VERSION" > "23" ]]; then
    SOURCES_FORMAT="deb822"
    MAIN_SOURCE="${SOURCES_LIST_D}/ubuntu.sources"
  else
    SOURCES_FORMAT="legacy"
    MAIN_SOURCE="$SOURCES_LIST"
  fi
  info "Sources format: ${SOURCES_FORMAT} (${MAIN_SOURCE})"
}

pick_mirror_url() {
  case "${MIRROR:-}" in
    tw|taiwan) echo "http://tw.archive.ubuntu.com/ubuntu" ;;
    *)         echo "http://archive.ubuntu.com/ubuntu" ;;
  esac
}

do_backup() {
  $DRY_RUN && { info "[DRY-RUN] would backup to ${BACKUP_DIR}"; return; }
  mkdir -p "$BACKUP_DIR"
  [ -f "$SOURCES_LIST" ]           && cp "$SOURCES_LIST" "$BACKUP_DIR/"
  [ -d "$SOURCES_LIST_D" ]         && cp -r "$SOURCES_LIST_D" "$BACKUP_DIR/"
  ok "Backed up to ${BACKUP_DIR}"
}

do_restore() {
  require_root
  local latest
  latest=$(ls -td /etc/apt/backup/*/ 2>/dev/null | head -1) \
    || die "No backup found in /etc/apt/backup/"
  info "Restoring from ${latest}"
  [ -f "${latest}/sources.list" ] && cp "${latest}/sources.list" "$SOURCES_LIST"
  [ -d "${latest}/sources.list.d" ] && cp -r "${latest}/sources.list.d/." "$SOURCES_LIST_D/"
  ok "Restored. Run: apt update"
}

ensure_sources_legacy() {
  local url; url=$(pick_mirror_url)
  local lines=(
    "deb ${url} ${UBUNTU_CODENAME} main restricted universe multiverse"
    "deb ${url} ${UBUNTU_CODENAME}-updates main restricted universe multiverse"
    "deb ${url} ${UBUNTU_CODENAME}-security main restricted universe multiverse"
    "deb ${url} ${UBUNTU_CODENAME}-backports main restricted universe multiverse"
  )
  for line in "${lines[@]}"; do
    if ! grep -Fxq "$line" "$SOURCES_LIST" 2>/dev/null; then
      info "Adding: ${line}"
      $DRY_RUN || echo "$line" >> "$SOURCES_LIST"
    fi
  done
}

ensure_sources_deb822() {
  local url; url=$(pick_mirror_url)
  if [ ! -f "$MAIN_SOURCE" ]; then
    info "Creating ${MAIN_SOURCE}..."
    $DRY_RUN && return
    cat > "$MAIN_SOURCE" <<EOF
Types: deb
URIs: ${url}
Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-security ${UBUNTU_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
  else
    info "${MAIN_SOURCE} already exists — skipping"
  fi
}

ensure_sources() {
  if [[ "$SOURCES_FORMAT" == "deb822" ]]; then
    ensure_sources_deb822
  else
    ensure_sources_legacy
  fi
}

comment_broken_sources() {
  info "Running apt update to detect broken sources..."
  local apt_output
  apt_output=$(apt update 2>&1 || true)
  echo "$apt_output" >> "$LOG_FILE"

  local fixed=0

  # Match lines like: E: Failed to fetch http://... 404 Not Found
  while IFS= read -r err_line; do
    local bad_url
    bad_url=$(echo "$err_line" | grep -oP 'https?://[^\s]+' | head -1) || continue
    [ -n "$bad_url" ] || continue

    warn "Broken source URL: ${bad_url}"

    # Search all .list files and sources.list
    local targets=("$SOURCES_LIST")
    while IFS= read -r f; do targets+=("$f"); done < <(find "$SOURCES_LIST_D" -name '*.list' 2>/dev/null)

    for f in "${targets[@]}"; do
      [ -f "$f" ] || continue
      if grep -q "$bad_url" "$f"; then
        info "Commenting out ${bad_url} in ${f}"
        $DRY_RUN || sed -i "s|^deb\(.*${bad_url}.*\)|# deb\1  # disabled: 404|g" "$f"
        (( fixed++ )) || true
      fi
    done
  done < <(echo "$apt_output" | grep -E 'E: Failed to fetch|404 Not Found|Unable to connect|Release file.*not valid')

  [ "$fixed" -gt 0 ] && ok "Commented out ${fixed} broken source(s)" \
    || info "No clearly broken sources detected"
}

try_update() {
  info "Running apt update..."
  if apt update 2>&1 | tee -a "$LOG_FILE"; then
    ok "apt update succeeded"
    return 0
  fi
  warn "apt update failed"
  return 1
}

### Main ###
parse_args "$@"
log "=== apt_source_repair start (dry-run=${DRY_RUN}) ==="
require_root
detect_ubuntu
do_backup
ensure_sources

if try_update; then
  ok "Done — no further repair needed"
  exit 0
fi

comment_broken_sources

if try_update; then
  ok "Repair successful"
  exit 0
else
  die "Repair failed. Check ${LOG_FILE} and consider: $0 --restore"
fi
