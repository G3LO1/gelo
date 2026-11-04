# Asking the user: AskUserQuestion rules

Shared by every skill in this plugin. The point: the user clicks instead of typing, and a decision is never buried in a paragraph.

## When to use it
Use AskUserQuestion for:
- **Choices**: path, style, rig, delivery mode (Rojo / Studio / paste-ready), where to design UI, audit scope, genre direction.
- **Confirmations that change things outside the chat**: overwriting `PRODUCTION_PLAN.md` / `LAUNCH_KIT.md` or any existing file, rewriting or deleting the user's scripts or models, creating or editing files in Figma, connecting Blender, applying audit patches, publishing or uploading anything.
- **"What next?"** at the end of a skill, with the hand-off skills as options.

Don't use it for:
- Facts the conversation or the project already contains.
- Free-form input (a game name, a pasted script, numbers like DAU). Ask for those in plain text, once.
- Questions with an obvious default and no real cost if wrong: pick the default, say so in one line, continue.

## Shape
- One call = one round. Group 1-4 independent questions in it; a question that depends on an earlier answer goes in the next call.
- 2-4 options per question. Don't add "Other" (it is automatic) or a "Skip" nobody needs.
- Recommended option first, label ending in "(Recommended)". Recommend because of something you saw (files, tools, earlier answers), and say what in the description.
- `header` is a 1-2 word tag ("Path", "Rig", "Overwrite"). `label` is 1-5 words. `description` says the consequence of picking it.
- `multiSelect: true` only when the options really can combine (several symptoms, several screens).
- Use `preview` for options that are easier to compare when seen (a palette with hex values, a layout sketch, a code snippet).
- Never put the question's answer in the question ("Should we use X, which is clearly best?").

## Templates

Overwrite confirmation
- question: "PRODUCTION_PLAN.md already exists. What should I do?"
- header: "Overwrite"
- options: "Write PRODUCTION_PLAN.v2.md (Recommended)" - keeps the old plan untouched; "Overwrite it" - replaces the file; "Update it in place" - edits only the sections that changed.

Patch approval
- question: "Apply the fixes for the 2 critical findings?"
- header: "Patch"
- options: "Fix criticals only (Recommended)" - smallest diff; "Fix all findings" - criticals plus high and medium; "Report only" - change nothing.

Missing tool
- question: "No Blender MCP server is connected. How should I do the 3D work?"
- header: "Blender"
- options: "Continue without Blender (Recommended)" - Studio tools and Creator Store assets; "Help me connect Blender" - walk through the setup; "Plan only" - a brief for someone else to build.

What next
- question: "The audit is done. What next?"
- header: "Next"
- options: the skill's hand-off targets, recommended first, plus "Nothing, we're done".

## After the answer
Use it. Don't repeat the question, don't ask for confirmation of the confirmation, and pass the answers along when handing over to another skill so it doesn't ask again.
