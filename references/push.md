# Push

## Flow

1. Determine the repository from {{USER_INTENT}} — either `arm` or `registry`.

2. Run the push script with the repository.

3. After the script finishes, display the result to the user based on the output:

   **On success** (changes pushed):

   ```text
   ✔ {label} → origin
   {commit_hash} · {commit_message}
   ```

   **Nothing to commit** (working tree clean):

   ```text
   ✔ nothing to commit — working tree clean
   ```

   **Aborted** (user declined push):

   ```text
   ⚠ aborted — changes remain staged
   ```

## Script

### `scripts/push.sh`

```bash
scripts/push.sh <repository>
```

| Arg | Values |
| ----- | -------- |
| `repository` | `arm`, `registry` |

**Repositories:**

- `arm` — pushes changes in the arm project directory (`$ROOT_DIR`)
- `registry` — pushes changes in `$HOME/agent-registry`

**Examples:**

```bash
scripts/push.sh arm
scripts/push.sh registry
```

**Error handling:**

- Invalid target → logs error, exits with code 1
- Target directory is not a git repository → logs error, exits with code 1
- `git` command not found → logs error, exits with code 1
- Potentially sensitive files (`.env`, `.key`, `.pem`, `.p12`, `credential`, `secret`, `password`) → warns before committing
