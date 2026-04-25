# Sync

## Flow

1. Run the sync script.

## Script

### `scripts/sync.sh`

```bash
scripts/sync.sh
```

**Examples:**

```bash
scripts/sync.sh
```

**Error handling:**

- Requires `yq` and `curl` → exits with error if missing
- Private repo without GitHub App credentials → may fail to fetch directory listing
- GitHub API failure → skips the directory, continues with the next
