# 🔧 Ubuntu APT Source Repair

Scripts to fix broken APT sources and manage GPG keys on Ubuntu.

## Scripts

| Script | Description |
|--------|-------------|
| `apt_source_repair.sh` | Repair broken APT sources, switch mirrors |
| `apt_key_manager.sh` | Add / remove / list APT GPG keys |

## Usage

```bash
# Fix broken sources
bash apt_source_repair.sh

# Manage GPG keys
bash apt_key_manager.sh --add <key-url>
```

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04

## License

MIT
