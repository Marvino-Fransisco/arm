# List

## Flow

1. Run `scripts/parse-registry.sh` to regenerate `registry.md` from `registry.yaml`, ensuring the content is up-to-date.

2. Ask the user what they want to list:

   ```json
   {
     "questions": [{
       "question": "What do you want to list?",
       "header": "Type",
       "multiple": true,
       "options": [
         { "label": "All (Recommended)", "description": "Show agents and skills" },
         { "label": "Agents", "description": "Show agents only" },
         { "label": "Skills", "description": "Show skills only" }
       ]
     }]
   }
   ```

3. Read `registry.md` and display the relevant section(s) based on the user's choice:
   - **All** — show the full content of `registry.md`
   - **Agents** — show only the `## Agents` section
   - **Skills** — show only the `## Skills` section
