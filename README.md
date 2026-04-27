# Agent Registry Manager (ARM)

An agent skill project for managing AI agent registries — install, update, delete, and sync **skills**, **custom agents**, **commands**, and **prompts** from GitHub repositories to your local machine. Share and reuse agent capabilities across platforms (opencode, claudecode) effortlessly.

This registry could be used **personally** or **team**, for private repository the team could use **GitHub App authentication** meanwhile there is no **GitHub App** needed for public repository, all team members could access the agent registry that listed in the registry.yaml

## What It Does

ARM lets you **share and use agent skills, custom agents, commands, and prompts everywhere**. It acts as a registry manager that downloads these components from contributor GitHub repos to your local platform directories — so any agent capability can be installed once and used across projects and platforms.

- **Skills** — Folders containing a `SKILL.md` and optional subfolders. Downloaded as entire directories via sparse checkout. Shared and reusable across projects.
- **Agents** — Markdown files defining an agent's persona, behavior, tools, and model settings. Downloaded as single `.md` files.
- **Commands** — Slash-command definitions that agents can execute. Shared from GitHub and installed locally.
- **Prompts** — Reusable prompt templates for consistent agent interactions.
- **registry.yaml** — Lists all available agents, skills, commands, and prompts grouped by contributor ID, with source URLs pointing to GitHub repos.
- **contributors.yaml** — Maps each contributor to GitHub App credentials and lists their repo URLs.
- **references/** — Step-by-step instructions for AI agents to follow when handling each sub-command interactively.

## How to Use

### Setup

1. Place this project in your platform's skills directory (e.g. `.opencode/skills/arm/`)
2. Create a `.env` file with your GitHub App credentials (see [docs/setup-github-app.md](docs/setup-github-app.md)):

   ```text
   MF_GH_APP_ID=123456
   MF_GH_APP_KEY_PATH=/home/you/.ssh/arm-gh-app-key.pem
   ```

3. Ensure you have the required tools: `bash`, `yq`, `curl`, `git`

### Invoking the Skill

Once installed, ARM registers as a skill command. Invoke it with `arm`:

To understand how to use `arm`, read the documentation here [help](references/help.md)

### Sub-commands

**`install`** — Installs one or more registries from contributor GitHub repos to your local platform directories. The agent reads the playbook and handles download, platform detection, and file placement.

**`update`** — Updates installed registries to the latest version. Backs up current files, downloads the newest version, shows a diff of changes, and rolls back on failure.

**`delete`** — Removes installed registries from local directories. Only items listed in `registry.yaml` can be deleted. Entries remain in the registry for future re-installation.

**`remove-registry`** — Removes items from `registry.yaml` and deletes the corresponding files from `~/agent-registry/`. Requires `--contributor` to specify which contributor's entries to remove. Automatically regenerates `registry.md` after removal.

**`sync`** — Scans all contributor repos for `agents/`, `skills/`, `commands/`, and `prompts/` directories and syncs entries into the local `registry.yaml`. Adds new items and removes items that no longer exist remotely.

**`list`** — Displays all available registries from `registry.yaml`.

**`help`** — Displays the help menu with usage instructions.

**`migrate`** — Migrates agents, skills, commands, and prompts from a platform config directory (`.opencode/`, `.claude/`) into the local agent-registry repository at `~/agent-registry/`. Only the specific files/folders being migrated are replaced — other items are left untouched. New items are automatically added to `registry.yaml` under the specified contributor.

**`push`** — Stages and pushes changes to either the `arm` or `agent-registry` repository with a summary and confirmation prompt.

**`pull`** - Pull the changes from `arm` or `agent-registry` repository

### Script-level usage

Each script also works standalone from the terminal. All registry-taking commands require a `<platform>` and optional `[scope]`:

```bash
# Install / Update / Delete
scripts/install.sh  <platform> [scope] <registry...>
scripts/update.sh   <platform> [scope] <registry...>
scripts/delete.sh   <platform> [scope] <registry...>

# Sync & list
scripts/sync.sh
scripts/parse-registry.sh [output_path]

# Remove from registry
scripts/remove-registry.sh --contributor <name> <registry...>

# Migrate local agents/skills to agent-registry repo
scripts/migrate.sh  --contributor <name> <scope> <platform> [items...]

# Push changes to git
scripts/push.sh     <arm|registry>
```

**Arguments:**

| Argument | Values | Description |
|----------|--------|-------------|
| `--contributor` | Any key from `contributors.yaml` | Contributor to associate migrated items with (required for `migrate` and `remove-registry`) |
| `platform` | `opencode`, `claudecode` | Target platform |
| `scope` | `project` (default), `global` | `project` = relative to project root, `global` = absolute `~/` |
| `registry` | `skill:{name}`, `agent:{name}`, `command:{name}`, `prompt:{name}` | Type:name pair |

### Generate registry documentation

```bash
scripts/parse-registry.sh              # outputs to registry.md
scripts/parse-registry.sh docs/other.md # custom output path
```

---

## Project Structure

```text
arm/
├── SKILL.md              # Skill definition — activates as /arm command
├── registry.md           # Auto-generated registry listing (from parse-registry.sh)
├── .env                  # GitHub App credentials (gitignored)
├── .env.example          # Example env file
├── configs/
│   ├── registry.yaml     # Registry index — agents & skills grouped by contributor
│   ├── contributors.yaml # Maps contributor IDs to GitHub App credentials & repos
│   └── default_dirs.yaml # Platform-specific target directories (project & global)
├── scripts/
│   ├── lib.sh            # Shared functions (download, GitHub App auth, URL parsing)
│   ├── utils.sh          # Color codes and logging helpers
│   ├── install.sh        # Install agents/skills from GitHub
│   ├── update.sh         # Update installed agents/skills (with backup & rollback)
│   ├── delete.sh         # Remove installed agents/skills
│   ├── sync.sh           # Sync registry.yaml from contributor repos
│   ├── remove-registry.sh# Remove items from registry.yaml and ~/agent-registry/
│   ├── migrate.sh        # Migrate agents/skills from local platform to agent-registry repo
│   ├── push.sh           # Push changes to arm or agent-registry repository
│   ├── pull.sh           # Pull changes from remote agent-registry repository
│   └── parse-registry.sh # Generate registry.md from registry.yaml
└── references/
    ├── install.md        # Reference for install flow
    ├── update.md         # Reference for update flow
    ├── delete.md         # Reference for delete flow
    ├── sync.md           # Reference for sync flow
    ├── remove-registry.md # Reference for remove-registry flow
    ├── list.md           # Reference for list flow
    ├── migrate.md        # Reference for migrate flow
    ├── push.md           # Reference for push flow
    ├── pull.md           # Reference for pull flow
    └── help.md           # Help menu and usage instructions
```

## Agent Registry Repo Structure

The agent-registry repository stores shared resources organized by type and platform:

```text
agent-registry/
├── agents/
│   ├── opencode/         # Agent definitions for opencode
│   └── claude/           # Agent definitions for claudecode
├── skills/               # Skill directories (each containing a SKILL.md)
├── commands/             # Slash-command definitions
└── prompts/              # Reusable prompt templates
```

## Registry YAML Structure

```yaml
registry:
  agents:
    <contributor-id>:        # e.g., "mf"
      <platform>:            # default, opencode, claudecode
        <agent-name>:
          description: "..."
          source: "https://github.com/.../blob/.../agent-name.md"
          skills: [skill-name]
  skills:
    <contributor-id>:
      <skill-name>:
        description: "..."
        source: "https://github.com/.../tree/.../skills/skill-name"
```

## Authentication

ARM authenticates via **GitHub App**. See [docs/setup-github-app.md](docs/setup-github-app.md) for full setup instructions.

| Scenario | How it works |
|----------|--------------|
| Public repo | Works without any authentication |
| Private repo | GitHub App generates short-lived installation tokens from `.env` credentials |

`contributors.yaml` maps contributors to GitHub App env vars and repos:

```yaml
contributors:
  mf:
    gh-app-id: MF_GH_APP_ID
    gh-app-key: MF_GH_APP_KEY_PATH
    gh-repo:
      - https://github.com/Marvino-Fransisco/agent-registry.git
```

## Supported Platforms

| Platform | Agents | Skills | Commands | Prompts |
|----------|--------|--------|----------|---------|
| opencode | `.opencode/agents/` | `.opencode/skills/` | `.opencode/commands/` | — |
| claudecode | `.claude/agents/` | `.claude/skills/` | `.claude/commands/` | `.claude/prompts/` |
| pi | - | `.pi/agent/skills/` | `.pi/agent/commands/` | `.pi/agent/prompts/` |

Each directory supports `project` (relative) and `global` (absolute `~/`) scopes.
