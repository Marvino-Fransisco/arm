# Help

This is a guide that must be display to user when they don't know how to use arm

```text
how to use:
  arm <sub-command> <registry...>
  arm <sub-command>
  arm push/pull <repository>

example:
  arm install skill:backend
  arm install skill:frontend agent:frontend-designer
  arm sync
  arm push arm
  arm migrate --contributor mf
  arm migrate --contributor mf agent:builder skill:research
  arm remove-registry --contributor mf skill:backend
  arm remove-registry --contributor mf agent:researcher skill:frontend

sub-commands:
  install <registry...> - install registry
  update  <registry...> - update current registry to the newest version
  delete  <registry...> - delete installed registry
  sync                  - sync the list of registries (registry.yaml) from all contributor's repository
  list                  - list the available registries
  migrate --contributor <name> [items...] - migrate agent/skill/command/prompt directories to ~/agent-registry
                           scope: local|global, platform: opencode|claude
                           optional items filter: agent:<n>, skill:<n>, command:<n>, prompt:<n>
  remove-registry --contributor <name> <registry...> - remove registry entries and files from registry.yaml and ~/agent-registry
  push                  - push 'arm' or '~/agent-registry' to github
  pull                  - pull 'arm' or '~/agent-registry' from github
  help                  - display help menu

registry:
  skill:{name}   - handle skill
  agent:{name}   - handle agent
  command:{name} - handle command
  prompt:{name}  - handle prompt

repository:
  arm       - your arm repository
  registry  - your registry repository
```
