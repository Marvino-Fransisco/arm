# Delete

## Flow

1. Extract the `{type}` and `{name}` from each validated registry parameter in {{USER_INTENT}}.

2. Run the delete script once with all registry items as arguments.

3. After the script finishes, display the result to the user based on the exit code:

   **On success** (all items deleted):

   ```text
   ✔ {count} item(s) deleted successfully.
   
   {registry} deleted from {platform} ({scope}).
   ...
   
   Note: entries remain in registry.yaml for future re-installation.
   ```

   **On partial failure** (some items failed):

   ```text
   ⚠ {failed_count} item(s) failed to delete.
   
   ✔ Deleted: {list of deleted items}
   ✘ Failed:  {list of failed items}
   
   Check the errors above for details.
   ```

## Script

### `scripts/delete.sh`

```bash
scripts/delete.sh <platform> [scope] <registry...>
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
scripts/delete.sh opencode skill:backend
scripts/delete.sh opencode local skill:backend agent:researcher
scripts/delete.sh claudecode global skill:frontend agent:designer
```

**Error handling:**

- Invalid registry pattern → logs error, continues with next item
- Item not found in `registry.yaml` → logs error, only registry items can be deleted
- Item not installed locally → logs error, continues with next item
- No directory configured for platform → logs error, continues
- Exits with code 1 if any item failed
