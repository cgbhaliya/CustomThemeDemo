---
description: Review pending changes, write a commit message, then commit + deploy the Shopify theme via shop.ps1
argument-hint: "[staging|production] [optional note about the change]"
---

Deploy this Shopify theme project using `shop.ps1`. Arguments: `$ARGUMENTS`
(If the first word is `staging` or `production`, that is the target environment; default is `production`. Any remaining text is a hint for the commit message.)

Follow these steps in order.

## 1. Check what is pending
Run these from the repo root and read the output:
- `git status --porcelain`
- `git diff HEAD --stat`
- `git diff HEAD` (for large diffs, look at the most relevant files rather than reading everything)
- `git log @{u}..HEAD --oneline` (commits not yet pushed; ignore the error if there is no upstream)

If there are no uncommitted changes AND no unpushed commits, tell me nothing has changed since the last deploy and ask whether I still want to redeploy. Stop until I answer.

If `config/settings_data.json` changed, warn me that shop.ps1 skips this file by default (it holds theme-editor settings) and ask whether to include it (`-IncludeSettings`).

## 2. Write the commit message
Base it on:
- the actual diff (what changed, in which sections/snippets/templates/assets), and
- what I asked for earlier in this conversation (the reason for the change, the client request, the bug being fixed).

Rules:
- One line, imperative mood, max ~72 characters, e.g. `Fix mobile menu overlap on product page`.
- Describe the change from the store's point of view (what a merchant or customer would notice), not just file names.
- If several unrelated things changed, summarise the main one and add "and N other tweaks".
- No double quotes, backticks or `$` characters in the message.
- Use my hint from the arguments if I gave one.

## 3. Ask me to confirm
Show me:
- a short bullet list of the changed files grouped by type (sections, snippets, templates, assets, other),
- the proposed commit message,
- the target environment (and a clear warning if it is production / the live theme).

Then ask: deploy with this message, edit it, or cancel? Wait for my answer. Do not deploy without my explicit yes.

## 4. Deploy
After I confirm, run exactly (works from both PowerShell and Git Bash):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 deploy "<message>" -Env <environment> -Yes
```

Add `-IncludeSettings` only if I agreed to it in step 1.
`-Yes` is used because I already confirmed here; the script cannot ask me itself from this chat.

## 5. Report
Tell me briefly: the commit hash, whether the git push and the Shopify push succeeded, and the deploy tag.
If the git push fails with an authentication error, tell me to run `.\shop.ps1 push` once in the VS Code terminal to sign in to GitHub, then run `/deploy` again. Do not try to work around authentication yourself.
