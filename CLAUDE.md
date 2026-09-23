# Shopify theme project

This repo is a Shopify theme managed with `shop.ps1` (Shopify CLI + git).

- Theme source: assets/, blocks/, config/, layout/, locales/, sections/, snippets/, templates/
- Store and theme IDs: settings block at the top of `shop.ps1` and `shopify.theme.toml`
- ALWAYS run the script with exactly this prefix (it is pre-approved in .claude/settings.json):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 <command> [options]`
- The script cannot read keyboard input when you run it. Ask me questions in chat and pass the
  answers as parameters. Never run a command that waits for input.

## Session start
A SessionStart hook runs `shop.ps1 session-check` (read-only) and prints the project status.
In your first reply, before working on my request, show that status briefly.
- If the project is installed: ask whether to pull the latest from GitHub and the live Shopify theme.
  Only if I say yes, run `... ./shop.ps1 autopull` and report the result. Never pull without my yes.
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
If any step fails with a login error (Shopify or GitHub), do not retry or work around it. Tell me to
run `.\shop.ps1 install` once in the VS Code terminal (Terminal -> New Terminal) to log in, then ask
you again.

## Pulling
When I ask to pull / get latest / sync: run `... ./shop.ps1 autopull` and report the result.

## Deploying
When I ask to deploy, publish, push live, or ship changes (in any wording), follow the steps in
`.claude/commands/deploy.md` exactly: check pending changes, write the commit message from the diff
and our conversation, get my confirmation, then run shop.ps1 deploy with `-Yes`.

## Saving work without deploying
When I ask to save / commit / push to git only: run `... ./shop.ps1 push "<message>"` with a message
written from the diff.

Never run `shopify theme push`, `shopify theme pull` or `git push` directly; always go through
`shop.ps1` so git is committed first and deploys are tagged.
