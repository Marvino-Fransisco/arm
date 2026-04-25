# Setting Up GitHub App Authentication

ARM uses **GitHub App** authentication to access contributor registries. This provides short-lived tokens, fine-grained permissions, and eliminates the need for manual token rotation.

---

## How It Works

```markdown
Contributor Repo ──► GitHub App (installed on repo) ──► ARM generates JWT
                                                           │
                                                           ▼
                                                  GitHub API exchanges JWT
                                                  for installation token
                                                           │
                                                           ▼
                                                  ARM uses token to download
                                                  (token auto-expires in 1 hour)
```

1. ARM reads your GitHub App ID and private key from `.env`
2. It generates a JWT signed with your private key
3. It calls the GitHub API to exchange the JWT for a short-lived installation token
4. The token is cached in `/tmp/arm-token-*` (auto-refreshed 60s before expiry)

---

## Step 1: Create a GitHub App

1. Go to **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**
2. Fill in:
   - **GitHub App name**: `ARM Registry` (or anything you like)
   - **Homepage URL**: arm repo URL
   - **Webhook**: uncheck **Active** (not needed)
3. Under **Permissions → Repository permissions**, set:
   - **Contents**: `Read-only` (to download agents/skills)
   - **Metadata**: `Read-only` (default)
4. Under **Where can this GitHub App be installed?**, choose:
   - **Any account** — if you want other orgs/users to install it
   - **Only on this account** — if only your org will use it
5. Click **Create GitHub App**

---

## Step 2: Generate a Private Key

1. On your GitHub App's settings page, scroll to **Private keys**
2. Click **Generate a private key**
3. A `.pem` file will download — **save it securely** (e.g., `~/.ssh/arm-gh-app-key.pem`)
4. Make it readable only by you:

   ```bash
   chmod 600 ~/.ssh/arm-gh-app-key.pem
   ```

> Note the **App ID** on the GitHub App settings page — you'll need it.

---

## Step 3: Install the App on Your Registry Repos

1. On the GitHub App settings page, click **Install App** in the sidebar
2. Select the account/org where your registry repos live
3. Choose **All repositories** or **Only select repositories** and pick your registry repos
4. Click **Install**

---

## Step 4: Configure ARM

### `.env`

Add your GitHub App credentials to `.env`:

```bash
MYTEAM_GH_APP_ID=123456
MYTEAM_GH_APP_KEY_PATH=/home/you/.ssh/arm-gh-app-key.pem
```

### `configs/contributors.yaml`

Map the env var names to each contributor:

```yaml
contributors:
  myteam:
    gh-app-id: MYTEAM_GH_APP_ID
    gh-app-key: MYTEAM_GH_APP_KEY_PATH
    gh-repo:
      - https://github.com/my-org/agent-registry.git
```

**That's it.** Run `sync.sh` or `install.sh` — ARM will automatically authenticate via the GitHub App.

---

## Multi-Contributor Setup

Each contributor (department, team, or external org) gets their own GitHub App:

```yaml
contributors:
  team-a:
    gh-app-id: TEAM_A_GH_APP_ID
    gh-app-key: TEAM_A_GH_APP_KEY_PATH
    gh-repo:
      - https://github.com/team-a/agent-registry.git
  team-b:
    gh-app-id: TEAM_B_GH_APP_ID
    gh-app-key: TEAM_B_GH_APP_KEY_PATH
    gh-repo:
      - https://github.com/team-b/agent-registry.git
```

```bash
# .env
TEAM_A_GH_APP_ID=111111
TEAM_A_GH_APP_KEY_PATH=/home/you/.ssh/team-a-key.pem
TEAM_B_GH_APP_ID=222222
TEAM_B_GH_APP_KEY_PATH=/home/you/.ssh/team-b-key.pem
```

Each team creates and manages their own GitHub App. You only need their App installed on their repos.

---

## Public Repos

If your registry repos are **public**, you don't need any authentication at all. ARM will download without a token. Auth is only required for **private** repos.

---

## Requirements

- `openssl` — for JWT signing (pre-installed on macOS and most Linux distros)
- `curl` — for GitHub API calls
- `yq` — for YAML parsing (already required by ARM)
