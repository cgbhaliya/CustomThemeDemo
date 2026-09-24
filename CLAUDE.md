# Shopify theme project

This repo is a Shopify theme managed with `shop.ps1` (Shopify CLI + git).

- Theme source: assets/, blocks/, config/, layout/, locales/, sections/, snippets/, templates/
- Store and theme IDs: settings block at the top of `shop.ps1` and `shopify.theme.toml`
- ALWAYS run the script with exactly this prefix (it is pre-approved in .claude/settings.json):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 <command> [options]`
- The script cannot read keyboard input when you run it. Ask me questions in chat and pass the
  answers as parameters. Never run a command that waits for input.

## Session start (new or resumed)
A SessionStart hook runs `shop.ps1 session-check` (read-only) whenever a session starts, is resumed
(e.g. after reopening VS Code) or is cleared, and prints a `[session-check]` status.
Every time a new `[session-check]` status appears, your NEXT reply must start by showing it briefly,
even in the middle of an ongoing conversation and whatever I asked:
- If the project is installed: ask with AskUserQuestion "Pull the latest from GitHub and the live
  Shopify theme first?" (options: "Yes, pull first" / "No, continue"). Wait for the answer before
  doing my request. Only if yes, run `... ./shop.ps1 autopull` and report the result, then do my
  request. Never pull without my yes.
- If the project is not installed: say so and offer to install it (see Installing).

## Installing
When I say install / set up / setup this project (in any wording), ask everything through the
AskUserQuestion tool (clickable options in the chat), never as plain text questions:
1. Store domain - only if `$StoreDomain` in shop.ps1 is empty. Use AskUserQuestion with the question
   "Which Shopify store is this project for?" and up to 3 options guessed from the repo folder name
   and git remote (e.g. repo `CustomThemeDemo` -> `customthemedemo.myshopify.com`). I can type a
   different one via Other; a bare handle like `customthemedemo` is fine.
2. Run `... ./shop.ps1 themes -SetStore <domain>` to get the theme list.
3. Theme selection - ONE AskUserQuestion call with two questions:
   - "Which theme is PRODUCTION?" - options = themes (LIVE theme first), label = theme name,
     description = `LIVE` or `unpublished` + the theme id. Max 4 options; if there are more themes,
     show the LIVE theme and the 3 most relevant, and I can type another id via Other.
   - "Which theme is STAGING?" - first option "No staging theme", then up to 3 unpublished themes.
4. Run `... ./shop.ps1 install -SetStore <domain> -SetTheme <productionId> [-SetStaging <stagingId>] -NoPrompt`
5. Report what was downloaded, the commit, and whether the GitHub push worked.
Listing themes needs only the Shopify login, not GitHub. If a command fails:
- `GITHUB_LOGIN_NEEDED` -> tell me to run `gh auth login --web` once in the VS Code terminal
  (Terminal -> New Terminal) and approve in the browser; when I say done, rerun the same command.
- Shopify login / "Could not list themes" -> tell me to run `shopify theme list --store <domain>`
  once in the VS Code terminal to log in; when I say done, rerun the same command.
Do not try to work around logins yourself, and keep the answers I already gave (store, themes).

## Pulling (git first, then Shopify - never overwrite without asking)
When I agree to the session pull, or ask to pull / get latest / sync:
1. Run `... ./shop.ps1 autopull`. It does `git pull`, then downloads the live theme into
   `.shopify/preview` and compares it with the local files. It does NOT overwrite anything.
2. If it prints `SHOPIFY_CHANGES: 0` or "up to date", tell me everything matches and continue.
3. Otherwise show me the list grouped as: changed on Shopify (M, local would be overwritten),
   new on Shopify (A), not on Shopify (D, local file would be deleted). For small M files you may
   show what changed with `git diff --no-index -- <path> .shopify/preview/<path>`.
4. Ask with AskUserQuestion "Take these changes from the live Shopify theme?" options:
   "Take all" / "Let me choose files" / "Keep my local files (skip)". Wait for my answer.
   - Take all -> run `... ./shop.ps1 apply-shopify`
   - Let me choose -> ask which files (multiSelect AskUserQuestion when 4 or fewer, otherwise a
     numbered list I answer in text), then run `... ./shop.ps1 apply-shopify -Files "path1,path2"`
   - Skip -> run nothing, and warn me that deploying would overwrite those live changes.
5. Report what was applied and the commit, then continue with my original request.

## Deploying
When I ask to deploy, publish, push live, or ship changes (in any wording), follow the steps in
`.claude/commands/deploy.md` exactly: check pending changes, write the commit message from the diff
and our conversation, get my confirmation, then run shop.ps1 deploy with `-Yes`.

## Saving work without deploying
When I ask to save / commit / push to git only: run `... ./shop.ps1 push "<message>"` with a message
written from the diff.

Never run `shopify theme push`, `shopify theme pull` or `git push` directly; always go through
`shop.ps1` so git is committed first and deploys are tagged.
