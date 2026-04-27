# Update

## Flow

1. Extract the `{type}` and `{name}` from each validated registry parameter in {{USER_INTENT}}.

2. Run the update script once with all registry items as arguments.

3. After the script finishes, display the result to the user based on the exit code:

   **On success** (all items updated):

   ```text
   ✔ {count} item(s) updated successfully.
   
   {registry} updated on {platform} ({scope}).
   ...
   ```

   **On partial failure** (some items failed):

   ```text
   ⚠ {failed_count} item(s) failed to update.
   
   ✔ Updated:  {list of updated items}
   ● Skipped:  {list of up-to-date items}
   ✘ Failed:   {list of failed items}
   
   Check the errors above for details.
   ```

## Script

### `scripts/update.sh`

```bash
scripts/update.sh <platform> [scope] <registry...>
```

| Arg | Values |
| ----- | -------- |
| `platform` | `opencode`, `claudecode`, `pi` |
| `scope` | `local` (default) or `global` |
| `registry` | one or more `type:name` pairs |

**Registry patterns:**

```text
skill:{name}
agent:{name}
command:{name}
prompt:{name}
```

**Examples:**

```bash
scripts/update.sh opencode skill:backend
scripts/update.sh opencode local skill:backend agent:researcher
scripts/update.sh claudecode global skill:frontend agent:designer
```

**Error handling:**

- Invalid registry pattern → logs error, continues with next item
- Item not found in `registry.yaml` → logs error, continues with next item
- Private repo without GitHub App credentials → logs error with hint, continues
- Item not installed locally → logs error with install hint, continues
- Download failure → rolls back to the backed-up version, continues
- No platform-specific agent → updates the `default` version with a warning
- Exits with code 1 if any item failed
