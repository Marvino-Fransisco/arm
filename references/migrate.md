# Migrate

## Flow

1. Choose the right directory from global variables based on {{AVAILABLE_PLATFORM}} and {{INSTALL_SCOPE}}. After that run the script

2. After the script finishes, display the result to the user based on the exit code:

   **On success** (all items migrated):

   ```text
   ✔ Migration complete.

   ✔ Copied:    {list of copied items}
   ◉ Registry:  {list of newly added registry entries}
   ● Skipped:   {list of skipped items}
   ```

   **On failure** (some items failed):

   ```text
   ⚠ Migration completed with errors.

   ✔ Copied:    {list of copied items}
   ◉ Registry:  {list of newly added registry entries}
   ● Skipped:   {list of skipped items}
   ✘ Failed:    {list of failed items}

   Check the errors above for details.
   ```

## Script

### `scripts/migrate.sh`

```bash
scripts/migrate.sh --contributor <name> <scope> <platform> [items...]
```

| Arg | Values |
| ----- | -------- |
| `--contributor` | Contributor key from `contributors.yaml` (required) |
| `scope` | `local` (current project) or `global` (home directory) |
| `platform` | `opencode` or `claude` |
| `items` | Optional filters: `agent:<name>`, `skill:<name>`, `command:<name>`, `prompt:<name>`. When omitted, all items are migrated. |

**Behavior:**

- Only the specific files/folders being migrated are replaced in the destination. Other items in `~/agent-registry` are left untouched.
- New items are automatically added to `registry.yaml` under the given contributor. Items already in the registry are not duplicated.
- If the contributor has no repo configured in `contributors.yaml`, the registry update is skipped with a warning.

**Destination mapping:**

```text
agents/   → ~/agent-registry/agents/{platform}/
skills/   → ~/agent-registry/skills/
commands/ → ~/agent-registry/commands/
prompts/  → ~/agent-registry/prompts/
```

**Examples:**

```bash
scripts/migrate.sh --contributor mf local opencode
scripts/migrate.sh --contributor mf local opencode agent:builder skill:research
scripts/migrate.sh --contributor mf global claude agent:designer command:review
```

**Error handling:**

- Missing `--contributor` flag → logs error and exits
- Invalid contributor key → logs error and exits
- Source directory does not exist → logs error and exits
- Source folder does not exist → logs warning, skips, continues
- Source folder is empty → logs warning, skips, continues
- Copy failure → logs error, marks item as failed, continues
- Contributor has no repo configured → logs warning, skips registry update for that item, continues
- Exits with code 1 if any item failed
