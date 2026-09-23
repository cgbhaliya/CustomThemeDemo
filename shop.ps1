# =============================================================================
#  shop.ps1 - Shopify theme + Git helper (single file, keep it in the repo root)
#
#  .\shop.ps1 install                  First time: set store, download theme, commit, push to git
#  .\shop.ps1 pull                     Get latest: git pull + download changes from Shopify
#  .\shop.ps1 push "message"           Save work to git only (commit + push), no Shopify
#  .\shop.ps1 deploy "message"         Commit + push to git, THEN publish theme to Shopify
#  .\shop.ps1 autopull                 Same as pull, but never prompts (run by Claude after you agree)
#  .\shop.ps1 themes -SetStore <domain>   List store themes (no prompts; used by Claude)
#  .\shop.ps1 install -SetStore <domain> -SetTheme <id> [-SetStaging <id>] -NoPrompt
#                                       Install with answers given up front (used by Claude)
#
#  Options:  -Env production|staging   -Yes (skip confirm)   -IncludeSettings
# =============================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "deploy", "pull", "push", "autopull", "session-check", "themes", "help")]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$Message,

    [string]$Env = "production",
    [switch]$Yes,
    [switch]$IncludeSettings,

    # Answers for install/themes so they can run without prompts
    [string]$SetStore,
    [string]$SetTheme,
    [string]$SetStaging,
    [switch]$NoPrompt
)

# =============================================================================
#  PROJECT SETTINGS - fill these in once per project, then commit this file.
#  Set StoreDomain; leave theme IDs "" and install will let you pick a theme
#  and save the IDs here automatically.
# =============================================================================
$StoreDomain       = "customthemedemo.myshopify.com"   # e.g. "client-one.myshopify.com"
$ProductionThemeId = "148640858181"   # e.g. "123456789012"   (find with: shopify theme list --store <domain>)
$StagingThemeId    = ""   # optional, e.g. "234567890123" - leave "" if no staging theme
# =============================================================================

# Native commands (git/shopify) are checked via $LASTEXITCODE, not exceptions
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$TomlFile = Join-Path $PSScriptRoot "shopify.theme.toml"

# ----------------------------------------------------------------- helpers ---
function Info($t)  { Write-Host $t -ForegroundColor Cyan }
function Ok($t)    { Write-Host $t -ForegroundColor Green }
function Warn($t)  { Write-Host $t -ForegroundColor Yellow }
function Fail($t)  { Write-Host $t -ForegroundColor Red; exit 1 }
function Check($what) { if ($LASTEXITCODE -ne 0) { Fail "$what failed (exit $LASTEXITCODE). Stopping." } }

function Write-NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Has-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Has-Changes { [bool](git status --porcelain) }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

# Makes sure git can authenticate to GitHub using GitHub CLI (gh).
# Runs once per command; safe to repeat.
$script:GitAuthDone = $false
$script:NonInteractive = $false
function Ensure-GitAuth {
    if ($script:GitAuthDone) { return }
    $url = "$(git remote get-url origin 2>&1)"
    if ($LASTEXITCODE -ne 0 -or $url -notmatch "^https://github\.com/") { $script:GitAuthDone = $true; return }

    if (-not (Has-Command "gh")) {
        if ($script:NonInteractive) { Fail "GitHub CLI not installed. Run .\shop.ps1 pull once in the VS Code terminal." }
        Warn "GitHub CLI not found - installing..."
        if (Has-Command "winget") {
            winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements
        }
        Refresh-Path
        if (-not (Has-Command "gh") -and (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe")) {
            $env:Path += ";$env:ProgramFiles\GitHub CLI"
        }
        if (-not (Has-Command "gh")) { Fail "Could not install GitHub CLI. Install it from https://cli.github.com and run again." }
    }

    gh auth status --hostname github.com 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if ($script:NonInteractive) { Fail "Not signed in to GitHub. Run .\shop.ps1 pull once in the VS Code terminal to sign in." }
        Info "`nSign in to GitHub - copy the code shown below, then approve in the browser..."
        gh auth login --hostname github.com --git-protocol https --web
        if ($LASTEXITCODE -ne 0) {
            Fail "GitHub login failed. Run this script from the VS Code terminal (not an AI chat), so you can complete the sign-in."
        }
    }

    # Tell git to use the GitHub CLI login for github.com
    gh auth setup-git --hostname github.com 2>&1 | Out-Null
    Check "gh auth setup-git"
    $script:GitAuthDone = $true
}

function Git-Push {
    if (-not (git remote)) { Warn "No git remote configured - commit kept locally."; return }
    Ensure-GitAuth
    git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { git push -u origin HEAD } else { git push }
    Check "git push"
}

function Commit-And-Push([string]$msg) {
    if (Has-Changes) {
        git add -A;          Check "git add"
        git commit -m $msg;  Check "git commit"
    } else {
        Write-Host "No local changes to commit." -ForegroundColor DarkGray
    }
    Git-Push
}

function Normalize-Store([string]$d) {
    $d = $d.Trim() -replace '^https?://', '' -replace '/.*$', ''
    if ($d -notmatch "\.myshopify\.com$") { $d = "$d.myshopify.com" }
    return $d
}

# Writes a value into the PROJECT SETTINGS block of this file and the current session
function Set-Setting([string]$name, [string]$value) {
    $text = [IO.File]::ReadAllText($PSCommandPath)
    $pattern = '(?m)^(\$' + $name + '\s*=\s*)"[^"]*"'
    if ($text -notmatch $pattern) { Fail "Could not find `$$name in shop.ps1 settings block." }
    $safe = $value -replace '["$`]', ''
    $text = [regex]::Replace($text, $pattern, '${1}"' + $safe + '"')
    [IO.File]::WriteAllText($PSCommandPath, $text, (New-Object System.Text.UTF8Encoding $false))
    Set-Variable -Name $name -Value $value -Scope Script
}

function Select-Theme($themes, [string]$title, [bool]$allowNone) {
    Write-Host ""
    Info $title
    for ($i = 0; $i -lt $themes.Count; $i++) {
        $t = $themes[$i]
        $role = if ($t.role -eq "live" -or $t.role -eq "main") { "LIVE" } else { $t.role }
        Write-Host ("  {0,2}) {1,-40} {2,-12} {3}" -f ($i + 1), $t.name, "[$role]", $t.id)
    }
    while ($true) {
        $range = if ($allowNone) { "0-$($themes.Count)" } else { "1-$($themes.Count)" }
        $pick = (Read-Host "Enter number ($range)").Trim()
        if ($allowNone -and ($pick -eq "0" -or $pick -eq "")) { return $null }
        $n = 0
        if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $themes.Count) { return $themes[$n - 1] }
        Warn "Invalid choice, try again."
    }
}

function Save-Toml([string]$store, [string]$prodId, [string]$stagingId) {
    $toml = "[environments.production]`nstore = `"$store`"`ntheme = `"$prodId`"`n"
    if ($stagingId -match "^\d+$") {
        $toml += "`n[environments.staging]`nstore = `"$store`"`ntheme = `"$stagingId`"`n"
    }
    Write-NoBom $TomlFile $toml
}

function Config-Filled { return ($StoreDomain.Trim() -and $ProductionThemeId.Trim()) }

# Settings block at the top of this file is the source of truth when filled in
function Apply-Config {
    if (-not (Config-Filled)) { return }
    $store = Normalize-Store $StoreDomain
    if ($ProductionThemeId.Trim() -notmatch "^\d+$") { Fail "ProductionThemeId in shop.ps1 must be a number." }
    Save-Toml $store $ProductionThemeId.Trim() $StagingThemeId.Trim()
}

function Require-Setup {
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "This folder is not a git repository." }
    Apply-Config
    if (-not (Test-Path $TomlFile)) { Fail "Project not set up yet. Run: .\shop.ps1 install" }
    if (-not (Has-Command "shopify")) { Fail "Shopify CLI not found. Run: .\shop.ps1 install" }
}

function Ensure-Tools {
    Info "Checking tools..."
    if (-not (Has-Command "git"))  { Fail "Git is not installed. Get it from https://git-scm.com" }
    if (-not (Has-Command "node")) { Fail "Node.js is not installed. Get the LTS from https://nodejs.org" }
    if (-not (Has-Command "shopify")) {
        Warn "Shopify CLI not found - installing..."
        npm install -g "@shopify/cli@latest"
        Check "Shopify CLI install"
        Refresh-Path
        if (-not (Has-Command "shopify")) { Fail "Shopify CLI installed, but not on PATH yet. Restart VS Code and run install again." }
    }
    Ok "git, node and shopify CLI are available."
    if (git remote) { Ensure-GitAuth; Ok "GitHub login OK." }
}

# Files that must never be uploaded to Shopify. NOTE: .shopifyignore applies to pull too,
# so only non-theme files belong here (never config/settings_data.json etc.).
$ShopifyIgnoreLines = @(
    "shop.ps1", "shopify.theme.toml",
    "*.md", "README*", "CLAUDE.md",
    ".claude/*", ".vscode/*", ".github/*", ".idea/*",
    ".gitignore", ".gitattributes", ".shopifyignore", ".editorconfig",
    ".env", ".env.*",
    "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "node_modules/*",
    "*.log", ".DS_Store", "Thumbs.db", "*.zip"
)
$GitIgnoreLines = @(
    "node_modules/", ".DS_Store", "Thumbs.db", ".env", ".env.*", "*.log",
    ".shopify/", ".claude/settings.local.json"
)

# Creates the file, or appends any missing lines to an existing one
function Merge-Lines([string]$path, [string[]]$lines) {
    $existing = @()
    if (Test-Path $path) { $existing = @(Get-Content $path | ForEach-Object { $_.Trim() }) }
    $missing = @($lines | Where-Object { $existing -notcontains $_ })
    if ($missing.Count -eq 0) { return }
    $text = ""
    if (Test-Path $path) {
        $text = [IO.File]::ReadAllText($path)
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
    }
    $text += ($missing -join "`n") + "`n"
    Write-NoBom $path $text
    Info "Updated $([IO.Path]::GetFileName($path)): added $($missing.Count) entr$(if ($missing.Count -eq 1) {'y'} else {'ies'})"
}

function Write-SupportFiles {
    Merge-Lines (Join-Path $PSScriptRoot ".gitignore") $GitIgnoreLines
    Merge-Lines (Join-Path $PSScriptRoot ".shopifyignore") $ShopifyIgnoreLines
}

# ----------------------------------------------------------------- actions ---
function Apply-SetParams {
    if ($SetStore)   { Set-Setting "StoreDomain" (Normalize-Store $SetStore) }
    if ($SetTheme)   {
        if ($SetTheme.Trim() -notmatch "^\d+$") { Fail "-SetTheme must be a numeric theme ID." }
        Set-Setting "ProductionThemeId" $SetTheme.Trim()
    }
    if ($SetStaging) {
        if ($SetStaging.Trim() -notmatch "^\d+$") { Fail "-SetStaging must be a numeric theme ID." }
        Set-Setting "StagingThemeId" $SetStaging.Trim()
    }
}

function Get-Themes([string]$store) {
    Info "Fetching themes from $store..."
    $raw = shopify theme list --store $store --json 2>&1
    $exit = $LASTEXITCODE
    $allText = ($raw | Out-String)
    if ($exit -ne 0) {
        Fail "Could not list themes (Shopify login needed or no access to $store). Run '.\shop.ps1 install' once in the VS Code terminal to log in.`n$allText"
    }
    try {
        # Shopify CLI writes hints to stderr; PowerShell wraps those as ErrorRecords.
        # Parse JSON only from the normal (stdout) lines.
        $stdout = ($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String)
        $start = $stdout.IndexOf("[")
        if ($start -lt 0) { throw "no JSON array in output" }
        $themes = @($stdout.Substring($start) | ConvertFrom-Json)
    } catch { Fail "Could not read the theme list from Shopify CLI:`n$allText" }
    if ($themes.Count -eq 0) { Fail "No themes found on $store." }
    return $themes
}

# Non-interactive theme list, for Claude to show in chat
function Do-Themes {
    $script:NonInteractive = $true
    if ($SetStore) { Set-Setting "StoreDomain" (Normalize-Store $SetStore) }
    if (-not $StoreDomain.Trim()) { Fail "NEED_STORE: pass -SetStore <handle>.myshopify.com" }
    Ensure-Tools
    $store = Normalize-Store $StoreDomain
    $themes = Get-Themes $store
    Write-Host "THEMES for ${store}:"
    foreach ($t in $themes) {
        $role = if ($t.role -eq "live" -or $t.role -eq "main") { "LIVE" } else { $t.role }
        Write-Host ("  {0}  [{1}]  {2}" -f $t.id, $role, $t.name)
    }
}

function Do-Install {
    if ($NoPrompt) { $script:NonInteractive = $true }
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Clone the repo first, then run install inside it." }
    Ensure-Tools

    # --- Answers passed as parameters (from Claude chat or scripts) ---
    Apply-SetParams

    # --- Store domain: from settings, or ask once and save into shop.ps1 ---
    if (-not $StoreDomain.Trim()) {
        if (Test-Path $TomlFile) {
            Ok "Using existing shopify.theme.toml"
        } elseif ($script:NonInteractive) {
            Fail "NEED_STORE: store domain not set. Pass -SetStore <handle>.myshopify.com"
        } else {
            $d = (Read-Host "Store domain (e.g. client-one.myshopify.com)").Trim()
            if (-not $d) { Fail "Store domain is required." }
            Set-Setting "StoreDomain" (Normalize-Store $d)
        }
    }

    # --- Theme IDs: from settings, or pick from a list and save into shop.ps1 ---
    if ($StoreDomain.Trim() -and -not $ProductionThemeId.Trim()) {
        if ($script:NonInteractive) {
            Fail "NEED_THEME: production theme not set. Run 'shop.ps1 themes' to list them, then pass -SetTheme <id>"
        }
        $themes = Get-Themes (Normalize-Store $StoreDomain)

        $prod = Select-Theme $themes "Select the PRODUCTION theme" $false
        Set-Setting "ProductionThemeId" "$($prod.id)"
        Ok "Production theme: $($prod.name) ($($prod.id))"

        $stg = Select-Theme $themes "Select a STAGING theme (0 = none)" $true
        if ($stg) {
            Set-Setting "StagingThemeId" "$($stg.id)"
            Ok "Staging theme: $($stg.name) ($($stg.id))"
        }
    }

    if (Config-Filled) {
        Apply-Config
        Ok "Store and theme saved in shop.ps1 and shopify.theme.toml"
    } elseif (-not (Test-Path $TomlFile)) {
        Fail "Store/theme not configured."
    }

    Write-SupportFiles

    if (Test-Path "layout\theme.liquid") {
        Ok "`nTheme files already in the repo - skipping download."
        Write-Host "Use '.\shop.ps1 pull' if you want to refresh from Shopify."
        # Make sure CLI is logged in to this store
        shopify theme list -e production | Out-Null
        if (Has-Changes) { Commit-And-Push "Save Shopify store/theme settings" }
        return
    }

    Info "`nDownloading theme from Shopify..."
    shopify theme pull -e production --path . --nodelete
    Check "shopify theme pull"

    Commit-And-Push "Initial theme pull from Shopify"
    Ok "`nInstall complete. Edit files, then run: .\shop.ps1 deploy `"your message`""
}

function Do-Deploy {
    Require-Setup
    Write-SupportFiles   # keep ignore files current; committed with this change
    if (-not $Message) { $Message = "Deploy to $Env $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

    Info "`n[1/2] Committing and pushing to git..."
    Commit-And-Push $Message

    if ($Env -eq "production" -and -not $Yes) {
        $ans = Read-Host "Deploy to PRODUCTION theme? (y/N)"
        if ($ans -notin @("y", "Y", "yes")) { Warn "Cancelled. (Git commit/push already done.)"; exit 0 }
    }

    Info "`n[2/2] Pushing theme to Shopify ($Env)..."
    $args2 = @("theme", "push", "-e", $Env, "--path", ".")
    if (-not $IncludeSettings) { $args2 += @("--ignore", "config/settings_data.json") }
    if ($Env -eq "production") { $args2 += "--allow-live" }
    & shopify @args2
    Check "shopify theme push"

    $tag = "deploy-$Env-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    git tag $tag
    if (git remote) { git push origin $tag 2>&1 | Out-Null }
    Ok "`nDeployed to $Env. Tagged as $tag"
}

function Do-Pull {
    Require-Setup
    if (Has-Changes) { Fail "You have uncommitted changes. Run push or deploy first." }

    Info "[1/2] Getting latest from git..."
    if (git remote) { Ensure-GitAuth; git pull; Check "git pull" }

    Info "`n[2/2] Downloading latest theme from Shopify ($Env)..."
    shopify theme pull -e $Env --path .
    Check "shopify theme pull"

    if (Has-Changes) {
        Warn "Shopify had changes not in git (e.g. theme editor edits) - saving them."
        Commit-And-Push "Pull latest from Shopify ($Env)"
    } else {
        Ok "Everything is up to date."
    }
}

function Do-Push {
    Require-Setup
    Write-SupportFiles   # keep ignore files current; committed with this change
    if (-not $Message) { $Message = "Update $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    Info "Committing and pushing to git (Shopify not touched)..."
    Commit-And-Push $Message
    Ok "Saved to git."
}

# Safe, non-interactive pull for the Claude Code SessionStart hook
function Do-AutoPull {
    $script:NonInteractive = $true
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "[auto-pull] Not a git repository - skipped."; exit 0 }
    if (-not (Config-Filled) -and -not (Test-Path $TomlFile)) {
        Write-Host "[auto-pull] Project not installed yet - run .\shop.ps1 install in the VS Code terminal. Skipped."; exit 0
    }
    if (-not (Has-Command "shopify")) {
        Write-Host "[auto-pull] Shopify CLI not installed - run .\shop.ps1 install in the VS Code terminal. Skipped."; exit 0
    }
    if (Has-Changes) {
        Write-Host "[auto-pull] Skipped: there are uncommitted local changes. Deploy or push them first, then run pull."
        git status --short
        exit 0
    }
    Write-Host "[auto-pull] Syncing latest from GitHub and Shopify ($Env)..."
    Do-Pull
    Write-Host "[auto-pull] Done. Latest commit: $(git log -1 --format='%h %s')"
}

# Read-only status check for the Claude Code SessionStart hook. Never pulls or changes anything.
function Do-SessionCheck {
    $script:NonInteractive = $true
    $pullCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./shop.ps1 autopull"
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "[session-check] Not a git repository."; exit 0 }
    if (-not (Config-Filled) -and -not (Test-Path $TomlFile)) {
        Write-Host "[session-check] Project not installed yet. In your first reply, tell the user and offer to install it here by following the 'Installing' steps in CLAUDE.md. Do not offer a pull."
        exit 0
    }

    $changes = @(git status --porcelain)
    $behind = "unknown"
    $env:GIT_TERMINAL_PROMPT = "0"
    if (git remote) {
        git fetch --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $n = git rev-list --count "HEAD..@{u}" 2>&1
            if ($LASTEXITCODE -eq 0) { $behind = "$n" }
        } else { $behind = "unknown (GitHub not reachable or not signed in)" }
    }

    Write-Host "[session-check] Shopify theme project status:"
    Write-Host "  - Uncommitted local changes: $($changes.Count)"
    Write-Host "  - Commits on GitHub not yet pulled: $behind"
    Write-Host "  - Live Shopify theme: not checked (the pull compares it)"
    Write-Host ""
    Write-Host "INSTRUCTION FOR CLAUDE: In your first reply of this session, before working on the user's request,"
    Write-Host "show this status in one or two lines and ask: 'Pull the latest from GitHub and the live Shopify theme now? (yes/no)'."
    Write-Host "Wait for the answer. If yes, run: $pullCmd  and report the result, then continue with the request."
    Write-Host "If no, continue with the request without pulling."
    if ($changes.Count -gt 0) {
        Write-Host "Note: there are uncommitted changes, so the pull will be skipped until they are deployed or pushed. Mention this when asking."
    }
    exit 0
}

function Show-Help {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 14 | ForEach-Object { $_ -replace '^#\s?', '' }
}

switch ($Action) {
    "install" { Do-Install }
    "pull"    { Do-Pull }
    "push"    { Do-Push }
    "deploy"  { Do-Deploy }
    "autopull" { Do-AutoPull }
    "session-check" { Do-SessionCheck }
    "themes"  { Do-Themes }
    default   { Show-Help }
}
