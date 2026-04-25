---
name: arm
description: >
  Activate this skill when receive `arm` as the first word in the message.
metadata:
  version: "1.0.0"
  author: Marvino-Fransisco
---

# Agent Registry Manager Skill

To manage agent registries, use the following rules, variables, and procedures:

## Variables

> The variable will be called via {{VARIABLE_NAME}}

> These are global variables, but you must fill it by yourself

| Variable      | Value |
| ------------- | ----- |
| USER_PLATFORM | empty |
| AGENT_SCOPE   | empty |
| USER_INTENT   | empty |
| CONTRIBUTOR   | empty |

> These are defined global variables.

| Variable           | Value                                      |
| ------------------ | ------------------------------------------ |
| CLAUDE_GLOBAL      | ~/.claude/                                 |
| CLAUDE_LOCAL       | ./.claude/                                 |
| OPENCODE_GLOBAL    | ~/.config/opencode                         |
| OPENCODE_LOCAL     | ./.opencode/agents                         |
| REGISTRY           | ~/agent-registry                           |
| AGENT_REGISTRY     | {{REGISTRY}}/agents/{{USER_PLATFORM}}      |
| SKILL_REGISTRY     | {{REGISTRY}}/skills                        |
| COMMAND_REGISTRY   | {{REGISTRY}}/commands                      |
| PROMPT_REGISTRY    | {{REGISTRY}}/prompts                       |
| COMMAND            | [command](references/help.md)              |
| AVAILABLE_PLATFORM | OpenCode, Claude Code                      |
| INSTALL_SCOPE      | Global, Local                              |

---

## Rules

> These rules are non-negotiable.

### 1. Escalation Behavior

> When in doubt, stop and ask. Proceeding with uncertainty is always worse than pausing.

You must stop and escalate to the user when:

- An assumption cannot be eliminated without information only the user can provide.
- Any phase checklist item cannot be completed due to missing context.
- User is not following the {{COMMAND}} guideline pattern.

You must never:

- Resolve uncertainty by making your best guess and proceeding silently.
- Assume that a missing file means the feature does not exist.
- Assume that silence from the user means confirmation.

### 2. File & Output Conventions

> Every output must be traceable, consistent, and stored in the correct location.

- Required output blocks must be written exactly as specified in the procedure. You must not paraphrase, shorten, or reformat them.

### 3. Workflow

> The workflow MUST execute the procedure sequentially from phase 1 to the final phase without skipping or reordering steps.
> Upon completion of the final phase, the procedure is considered terminated.
> If a new user input (trigger) is received after termination, the workflow MUST restart from Phase 1 and repeat the procedure. 

Do not modify any codes or scripts

Do not read the references again if they have already been processed.

Do not request the user’s platform or scope when the following variables are already known, unless the user explicitly indicates otherwise:

- {{AGENT_SCOPE}}
- {{USER_PLATFORM}}
- {{CONTRIBUTOR}}

---

## Procedure

### Phase 1 - Understand user's request

> You must focus on understanding the user's actual intention.

**Failure to complete phase 1 correctly will create unclear user's intent. This will invalidate all subsequent work.**

- [ ] Read and understand the user’s message, then define their intent as {{USER_INTENT}}.
- [ ] If {{USER_INTENT}} is unclear or not expressed using {{COMMAND}}, provide the {{COMMAND}} to the user.
- [ ] If {{USER_INTENT}} is clear but not expressed using {{COMMAND}}, provide a copy-pasteable command based on {{COMMAND}} for the user.
- [ ] If {{USER_INTENT}} already follows {{COMMAND}}, proceed to the next phase.

---

### Phase 2 - Command validation

> You must validate the {{USER_INTENT}} and make sure to follow the {{COMMAND}}.

**Failure to complete phase 2 correctly will create wrong command. This will invalidate all subsequent work.**

#### Validation Rules

- [ ] Ensure the command starts with `arm`.  
- [ ] Ensure a valid `<sub-command>` is provided.  

---

#### Sub-command Validation

- [ ] Verify that `<sub-command>` is one of the following:
  - `install`
  - `update`
  - `delete`
  - `sync`
  - `list`
  - `migrate`
  - `push`
  - `help`

- [ ] If the `<sub-command>` is invalid or missing, return the correct usage format.

---

#### Registry Validation (`<registry...>`)

- [ ] If {{USER_INTENT}} includes `<registry...>`, ensure each registry follows the correct pattern:
  - `skill:{name}`
  - `agent:{name}`
  - `command:{name}`
  - `prompt:{name}`

- [ ] Ensure `{name}` is not empty.  
- [ ] Ensure multiple registries are separated by spaces.  
- [ ] Reject any registry that does not match the defined prefixes (`skill:`, `agent:`, `command:`, `prompt:`).  

---

#### Sub-command Argument Rules

- [ ] `install`, `update`, `delete`
  - Must include at least one `<registry...>`.  
  - Reject if no registry is provided.  

- [ ] `sync`, `list`, `help`
  - Must NOT include any additional arguments.
  - Reject if extra arguments are provided.

- [ ] `migrate`
  - Must include `--contributor <name>`.
  - Optionally include `<registry...>` filters.
  - Reject if `--contributor` is missing.  

- [ ] `push`
  - Must include exactly one `<repository>`.  
  - Valid values:
    - `arm`
    - `registry`
  - Reject if missing or invalid repository value.  

---

#### Structural Validation

- [ ] Ensure arguments follow the correct order:

`arm <sub-command> <arguments>`

- [ ] Reject any unknown flags or unexpected tokens.  
- [ ] Ensure there are no duplicated or conflicting arguments.  

---

#### Fallback Handling

- [ ] If {{USER_INTENT}} does not follow {{COMMAND}}:
- Provide the correct command format.  
- Include a copy-pasteable example.  

- [ ] If {{USER_INTENT}} is partially valid:
- Correct only the invalid portion.  
- Preserve valid inputs.

---

### Phase 3 - Context resolution

> Ensure all required context variables are defined before proceeding.

**Failure to complete Phase 3 correctly will result in missing context and invalidate all subsequent steps.**

- [ ] Check whether {{USER_PLATFORM}}, {{AGENT_SCOPE}}, and {{CONTRIBUTOR}} are already defined.

- [ ] If all required variables are already defined:
  - Skip this phase and proceed to the next phase.  

- [ ] If any required variable is undefined:
  - Prompt the user to provide the missing information.  
  - Use an interactive selection format.  
  - Wait for the user’s response before proceeding.  

---

#### Platform Selection

- [ ] If {{USER_PLATFORM}} is undefined:
  - Prompt the user with available options from {{AVAILABLE_PLATFORM}}.

    ```text
    Question: What platform do you use?
    Options:

    OpenCode
    ...
    ```
---

#### Scope Selection

- [ ] If {{AGENT_SCOPE}} is undefined:
  - Prompt the user with available options from {{INSTALL_SCOPE}}. 

    ```text
    Question: What is the scope?
    Options:

    Local (Recommended)
    ...
    ```

---

#### Contributor Selection

- [ ] If {{CONTRIBUTOR}} is undefined and {{USER_INTENT}} requires it (e.g., `migrate`):
  - Read `configs/contributors.yaml` to get available contributor keys.
  - Prompt the user with the available options.

    ```text
    Question: Which contributor is this for?
    Options:

    mf
    ...
    ```

---

#### Storage Rules

- [ ] Store the user’s selections in:
  - {{USER_PLATFORM}}
  - {{AGENT_SCOPE}}
  - {{CONTRIBUTOR}}

- [ ] Do not proceed until all required variables are defined.  

---

### Phase 4 - Read reference

> You must read the right references based on {{USER_INTENT}}

**Failure to complete phase 4 correctly will create wrong command execution later. This will invalidate all subsequent work.**

- [ ] Read the right references in `/references`

**Required output before proceeding:**

> "Reference read
> [reference]

---

### Phase 5 - Execution

> Follow the execution flow from reference

**Failure to complete phase 5 correctly will invalidate all subsequent work.**

- [ ] Execute flow from reference

---

### Phase 6 - Report

> Provide result summary to user

**Failure to complete phase 6 correctly will invalidate all subsequent work.**

- [ ] Provide report from the script output
- [ ] Empty the {{USER_INTENT}}
