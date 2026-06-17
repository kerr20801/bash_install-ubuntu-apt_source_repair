#!/bin/bash
# apt_key_manager.sh — manage APT GPG keys for Ubuntu 20.04 / 22.04 / 24.04
#
# The deprecated `apt-key` command was removed in Ubuntu 24.04.
# This script uses the modern /etc/apt/keyrings/ approach.
#
# Usage:
#   sudo bash apt_key_manager.sh                       # auto-fix NO_PUBKEY + refresh known keys
#   sudo bash apt_key_manager.sh --add <url> <name>    # install key from URL
#   sudo bash apt_key_manager.sh --remove <name>       # remove key by name
#   sudo bash apt_key_manager.sh --list                # list installed keys
#   sudo bash apt_key_manager.sh --fix-pubkeys         # only fix NO_PUBKEY errors
#   sudo bash apt_key_manager.sh --update-known        # only refresh Docker/GitLab/Google keys

set -euo pipefail

LOG_FILE="/var/log/apt_key_manager.log"
KEYRING_DIR="/etc/apt/keyrings"
# trusted.gpg.d: used only for auto-fixed NO_PUBKEY (global trust, no source-file edit needed)
TRUSTED_DIR="/etc/apt/trusted.gpg.d"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "ℹ️  $*"; }
ok()   { log "✅ $*"; }
warn() { log "⚠️  $*"; }
die()  { log "❌ $*"; exit 1; }

require_root() {
  [ "$EUID" -eq 0 ] || die "Run as root: sudo bash $0 $*"
}

ensure_keyrings_dir() {
  install -d -m 0755 "$KEYRING_DIR"
}

# Fetch a key from a URL, dearmor, and save to /etc/apt/keyrings/<name>.gpg
# Prints the saved path.
cmd_add() {
  local url="${1:-}" name="${2:-}"
  [[ -n "$url" && -n "$name" ]] || die "Usage: $0 --add <key-url> <name>"
  ensure_keyrings_dir

  local dest="${KEYRING_DIR}/${name}.gpg"
  info "Fetching key from ${url} → ${dest}"

  # Determine if source is already binary (armored vs dearmored)
  local tmp; tmp=$(mktemp)
  curl -fsSL "$url" -o "$tmp" || die "curl failed for ${url}"

  if file "$tmp" | grep -q "PGP public key block.*armor"; then
    gpg --batch --yes --dearmor -o "$dest" "$tmp"
  else
    cp "$tmp" "$dest"
  fi
  rm -f "$tmp"
  chmod 0644 "$dest"

  ok "Key installed: ${dest}"
  info "Add 'Signed-By: ${dest}' to the corresponding .sources file, or"
  info "add '[signed-by=${dest}]' to the corresponding .list file."
}

cmd_remove() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "Usage: $0 --remove <name>"
  local dest="${KEYRING_DIR}/${name}.gpg"
  [ -f "$dest" ] || die "Key not found: ${dest}"
  rm -f "$dest"
  ok "Removed: ${dest}"
}

cmd_list() {
  info "Keys in ${KEYRING_DIR}:"
  if compgen -G "${KEYRING_DIR}/*.gpg" > /dev/null 2>&1; then
    for f in "${KEYRING_DIR}"/*.gpg; do
      local fingerprint
      fingerprint=$(gpg --no-default-keyring --keyring "$f" --list-keys --with-colons 2>/dev/null \
        | awk -F: '/^fpr/{print $10; exit}') || fingerprint="(cannot read)"
      printf "  %-40s  %s\n" "$(basename "$f")" "$fingerprint"
    done
  else
    echo "  (none)"
  fi

  info "Legacy keys in ${TRUSTED_DIR}:"
  if compgen -G "${TRUSTED_DIR}/auto-fixed-*.gpg" > /dev/null 2>&1; then
    for f in "${TRUSTED_DIR}"/auto-fixed-*.gpg; do echo "  $(basename "$f")"; done
  else
    echo "  (none)"
  fi
}

# Auto-fix NO_PUBKEY errors from apt update.
# Stores recovered keys in /etc/apt/trusted.gpg.d/ so no source file edits needed.
cmd_fix_pubkeys() {
  info "Running apt update to scan for NO_PUBKEY errors..."
  local apt_output
  apt_output=$(apt update 2>&1 || true)
  echo "$apt_output" >> "$LOG_FILE"

  local key_ids
  key_ids=$(echo "$apt_output" \
    | grep -oP 'NO_PUBKEY \K[0-9A-F]+' \
    | sort -u) || true

  if [[ -z "$key_ids" ]]; then
    ok "No NO_PUBKEY errors found"
    return 0
  fi

  local fixed=0
  while IFS= read -r key_id; do
    [[ -n "$key_id" ]] || continue
    info "Fetching missing key: ${key_id}"

    local dest="${TRUSTED_DIR}/auto-fixed-${key_id}.gpg"
    if gpg --batch \
         --keyserver hkp://keyserver.ubuntu.com:80 \
         --recv-keys "$key_id" 2>>"$LOG_FILE" \
    && gpg --batch --yes \
         --export "$key_id" \
         | gpg --batch --yes --dearmor -o "$dest" 2>>"$LOG_FILE"; then
      chmod 0644 "$dest"
      ok "Imported key ${key_id} → ${dest}"
      (( fixed++ )) || true
    else
      warn "Could not fetch key ${key_id} from keyserver — try: gpg --keyserver hkp://pgp.mit.edu --recv-keys ${key_id}"
    fi
  done <<< "$key_ids"

  [ "$fixed" -gt 0 ] && ok "Fixed ${fixed} missing key(s)" || warn "No keys were fixed"
}

# Refresh well-known third-party keys using their canonical URLs.
# Only runs if the corresponding source file exists.
cmd_update_known() {
  ensure_keyrings_dir

  # Docker
  local docker_src=""
  for f in /etc/apt/sources.list.d/docker.list \
            /etc/apt/sources.list.d/docker.sources; do
    [ -f "$f" ] && { docker_src="$f"; break; }
  done
  if [[ -n "$docker_src" ]]; then
    info "Refreshing Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --batch --yes --dearmor -o "${KEYRING_DIR}/docker.gpg"
    chmod 0644 "${KEYRING_DIR}/docker.gpg"
    ok "Docker key → ${KEYRING_DIR}/docker.gpg"
  fi

  # GitLab CE
  if [ -f /etc/apt/sources.list.d/gitlab_gitlab-ce.list ]; then
    info "Refreshing GitLab GPG key..."
    curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey \
      | gpg --batch --yes --dearmor -o "${KEYRING_DIR}/gitlab.gpg"
    chmod 0644 "${KEYRING_DIR}/gitlab.gpg"
    ok "GitLab key → ${KEYRING_DIR}/gitlab.gpg"
  fi

  # Google Chrome
  if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
    info "Refreshing Google Chrome GPG key..."
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --batch --yes --dearmor -o "${KEYRING_DIR}/google-chrome.gpg"
    chmod 0644 "${KEYRING_DIR}/google-chrome.gpg"
    ok "Google key → ${KEYRING_DIR}/google-chrome.gpg"
  fi
}

### Main ###
log "=== apt_key_manager start ==="
require_root

if [[ $# -eq 0 ]]; then
  cmd_fix_pubkeys
  cmd_update_known
  exit 0
fi

case "${1:-}" in
  --add)           shift; cmd_add "$@" ;;
  --remove)        shift; cmd_remove "$@" ;;
  --list)          cmd_list ;;
  --fix-pubkeys)   cmd_fix_pubkeys ;;
  --update-known)  cmd_update_known ;;
  -h|--help)
    grep '^# ' "$0" | head -15 | sed 's/^# //'
    exit 0 ;;
  *) die "Unknown option: $1  (run $0 --help)" ;;
esac
