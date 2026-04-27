# Install

## Flow

1. Extract the `{type}` and `{name}` from each validated registry parameter in {{USER_INTENT}}.

2. Run the install script once with all registry items as arguments.

3. After the script finishes, display the result to the user based on the exit code:

   **On success** (all items installed):

   ```text
   ✔ {count} item(s) installed successfully.
   
   {registry} installed to {platform} ({scope}).
   ...
   ```

   **On partial failure** (some items failed):

   ```text
   ⚠ {failed_count} item(s) failed to install.
   
   ✔ Installed: {list of installed items}
   ✘ Failed:    {list of failed items}
   
   Check the errors above for details.
   ```

## Script

### `scripts/install.sh`

```bash
scripts/install.sh <platform> [scope] <registry...>
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
scripts/install.sh opencode skill:backend
scripts/install.sh opencode local skill:backend agent:researcher
scripts/install.sh claudecode global skill:frontend skill:backend agent:designer
```

**Error handling:**

- Invalid registry pattern → logs error, continues with next item
- Item not found in `registry.yaml` → logs error, continues with next item
- Private repo without GitHub App credentials → logs error with hint to configure `.env`, continues
- Download failure → cleans up partial files, continues
- No platform-specific agent → installs the `default` version with a warning
- Exits with code 1 if any item failed
