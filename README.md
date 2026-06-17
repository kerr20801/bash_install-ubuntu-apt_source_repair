# Ubuntu APT Source Repair

Scripts to fix broken APT sources and manage GPG keys on Ubuntu 20.04 / 22.04 / 24.04.

## Scripts

| Script | Description |
|--------|-------------|
| `apt_source_repair.sh` | Repair broken sources, switch mirrors, backup / restore |
| `apt_key_manager.sh` | Add / remove / list APT GPG keys (Ubuntu 24.04 compatible) |

---

## apt_source_repair.sh

```bash
# Repair broken sources (auto-backup before any change)
sudo bash apt_source_repair.sh

# Dry-run: show what would change, no writes
sudo bash apt_source_repair.sh --check

# Restore from the most recent backup
sudo bash apt_source_repair.sh --restore

# Use Taiwan mirror instead of global archive
sudo bash apt_source_repair.sh --mirror tw
```

**What it does:**
1. Detects Ubuntu version and sources format (legacy `.list` vs DEB822 `.sources` for 24.04+)
2. Backs up `/etc/apt/sources.list` and `sources.list.d/` to `/etc/apt/backup/<timestamp>/`
3. Ensures base Ubuntu sources are present (adds missing entries)
4. Runs `apt update` — if it fails, parses errors to comment out broken source lines
5. Runs `apt update` again to verify the fix

---

## apt_key_manager.sh

`apt-key` was deprecated in Ubuntu 22.04 and **removed in Ubuntu 24.04**.  
This script uses the modern `/etc/apt/keyrings/` approach.

```bash
# Auto-fix NO_PUBKEY errors + refresh Docker/GitLab/Google keys
sudo bash apt_key_manager.sh

# Install a key from URL (e.g., for a new third-party repo)
sudo bash apt_key_manager.sh --add https://example.com/key.gpg myrepo

# List installed keys
sudo bash apt_key_manager.sh --list

# Remove a key
sudo bash apt_key_manager.sh --remove myrepo

# Only fix NO_PUBKEY errors (skips known-key refresh)
sudo bash apt_key_manager.sh --fix-pubkeys

# Only refresh Docker / GitLab / Google keys
sudo bash apt_key_manager.sh --update-known
```

**What it does (default mode):**
1. Runs `apt update` and parses `NO_PUBKEY` errors
2. Fetches missing keys from `keyserver.ubuntu.com` → `/etc/apt/trusted.gpg.d/`
3. Refreshes Docker, GitLab, and Google keys in `/etc/apt/keyrings/`

**After `--add`:** the key is stored in `/etc/apt/keyrings/<name>.gpg`.  
You still need to add `Signed-By: /etc/apt/keyrings/<name>.gpg` to the corresponding `.sources` file (or `[signed-by=...]` in a `.list` file).

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 (Debian 11+ compatible)
- `gpg`, `curl` — auto-installed if missing

## License

MIT
