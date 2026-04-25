# Remove Registry

## Flow

1. Extract the `{type}` and `{name}` from each validated registry parameter in {{USER_INTENT}}.

2. Determine the `{contributor}` key (required).

3. Run the remove-registry script once with the contributor and all registry items as arguments.

4. After the script finishes, display the result to the user based on the exit code:

   **On success** (all items removed):

   ```text
   ✔ {count} item(s) removed from registry.

   {registry} removed from contributor '{contributor}'.
   ...
   ```

   **On partial failure** (some items failed):

   ```text
   ⚠ {failed_count} item(s) failed to remove.

   ✔ Removed: {list of removed items}
   ✘ Failed:  {list of failed items}

   Check the errors above for details.
   ```

## Script

### `scripts/remove-registry.sh`

```bash
scripts/remove-registry.sh --contributor <name> <registry...>
```

| Arg | Values |
| ----- | -------- |
| `--contributor` | contributor key in `registry.yaml` (required) |
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
scripts/remove-registry.sh --contributor mf skill:backend
scripts/remove-registry.sh --contributor mf agent:researcher skill:frontend
```

**Error handling:**

- Missing `--contributor` → prints error and usage, exits
- Invalid contributor key → prints error, exits
- Invalid registry pattern → logs error, continues with next item
- Item not found for contributor in `registry.yaml` → logs error, continues with next item
- File/directory not found in `~/agent-registry/` → logs warning (already removed), continues
- Automatically runs `parse-registry.sh` after removal to regenerate `registry.md`
- Exits with code 1 if any item failed
