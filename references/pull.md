# Pull

## Flow

1. Determine the repository from {{USER_INTENT}} — either `arm` or `registry`.

2. Run the pull script with the repository.

3. After the script finishes, display the result to the user based on the output:

   **On success** (commits pulled):

   ```text
   ✔ {label} ← origin
   {old_hash} → {new_hash} · {count} commit(s) pulled
   ```

   **Already up to date** (no new commits):

   ```text
   ✔ already up to date — no new commits
   ```

   **Aborted** (user declined pull):

   ```text
   ⚠ aborted — no changes pulled
   ```

## Script

### `scripts/pull.sh`

```bash
scripts/pull.sh <repository>
```

| Arg | Values |
| ----- | -------- |
| `repository` | `arm`, `registry` |

**Repositories:**

- `arm` — pulls changes in the arm project directory (`$ROOT_DIR`)
- `registry` — pulls changes in `$HOME/agent-registry`

**Examples:**

```bash
scripts/pull.sh arm
scripts/pull.sh registry
```

**Error handling:**

- Invalid target → logs error, exits with code 1
- Target directory is not a git repository → logs error, exits with code 1
- `git` command not found → logs error, exits with code 1
- Pull with conflicts (ff-only fails) → git will error and exit with code 1
