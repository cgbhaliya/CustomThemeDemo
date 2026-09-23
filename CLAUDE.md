# Shopify theme project

This repo is a Shopify theme managed with `shop.ps1` (Shopify CLI + git).

- Theme source: assets/, blocks/, config/, layout/, locales/, sections/, snippets/, templates/
- Store and theme IDs: settings block at the top of `shop.ps1` and `shopify.theme.toml`
- Run the script with: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 <command>`

## Session start
A SessionStart hook runs `shop.ps1 session-check` (read-only) and prints the project status.
In your first reply, before working on my request, show that status briefly and ask whether to
pull the latest from GitHub and the live Shopify theme. Only if I say yes, run
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 autopull` and report the result.
If I say no, continue without pulling. Never pull without my yes.

## Deploying
When I ask to deploy, publish, push live, or ship changes (in any wording), follow the steps in
`.claude/commands/deploy.md` exactly: check pending changes, write the commit message from the diff
and our conversation, get my confirmation, then run shop.ps1 deploy.

Never run `shopify theme push` or `git push` directly; always go through `shop.ps1` so git is
committed first and the deploy is tagged.

`shop.ps1 install` asks questions and may need a browser login, so ask me to run it myself in the
VS Code terminal instead of running it from here.
