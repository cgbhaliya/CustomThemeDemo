# =============================================================================
#  shop.ps1 - Shopify theme + Git helper (single file, keep it in the repo root)
#
#  .\shop.ps1 install                  First time: set store, download theme, commit, push to git
#  .\shop.ps1 pull                     Get latest: git pull + download changes from Shopify
#  .\shop.ps1 push "message"           Save work to git only (commit + push), no Shopify
#  .\shop.ps1 deploy "message"         Commit + push to git, THEN publish theme to Shopify
#
#  Options:  -Env production|staging   -Yes (skip confirm)   -IncludeSettings
# =============================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "deploy", "pull", "push", "help")]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$Message,

    [string]$Env = "production",
    [switch]$Yes,
    [switch]$IncludeSettings
)

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

function Git-Push {
    if (-not (git remote)) { Warn "No git remote configured - commit kept locally."; return }
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

function Require-Setup {
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "This folder is not a git repository." }
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
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (Has-Command "shopify")) { Fail "Shopify CLI installed, but not on PATH yet. Restart VS Code and run install again." }
    }
    Ok "git, node and shopify CLI are available."
}

function Write-SupportFiles {
    if (-not (Test-Path ".gitignore")) {
        Write-NoBom ".gitignore" "node_modules/`n.DS_Store`nThumbs.db`n.env`n*.log`n.shopify/`n"
    }
    # Keep non-theme files out of Shopify uploads
    if (-not (Test-Path ".shopifyignore")) {
        Write-NoBom ".shopifyignore" "shop.ps1`n*.md`n.vscode/`n.gitignore`n.shopifyignore`nshopify.theme.toml`n"
    }
}

# ----------------------------------------------------------------- actions ---
function Do-Install {
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Clone the repo first, then run install inside it." }
    Ensure-Tools

    if (-not (Test-Path $TomlFile)) {
        Info "`nStore setup"
        $store = (Read-Host "Store domain (e.g. client-one.myshopify.com)").Trim()
        if ($store -notmatch "\.myshopify\.com$") { $store = "$store.myshopify.com" }

        Info "`nFetching themes from $store (a browser login may open)..."
        shopify theme list --store $store
        Check "shopify theme list"

        $themeId = (Read-Host "`nTheme ID to use as PRODUCTION").Trim()
        if ($themeId -notmatch "^\d+$") { Fail "Theme ID must be a number." }
        $stagingId = (Read-Host "Theme ID for STAGING (press Enter to skip)").Trim()

        $toml = "[environments.production]`nstore = `"$store`"`ntheme = `"$themeId`"`n"
        if ($stagingId -match "^\d+$") {
            $toml += "`n[environments.staging]`nstore = `"$store`"`ntheme = `"$stagingId`"`n"
        }
        Write-NoBom $TomlFile $toml
        Ok "Saved shopify.theme.toml"
    } else {
        Ok "Using existing shopify.theme.toml"
    }

    Write-SupportFiles

    if (Test-Path "layout\theme.liquid") {
        Ok "`nTheme files already in the repo - skipping download."
        Write-Host "Use '.\shop.ps1 pull' if you want to refresh from Shopify."
        # Make sure CLI is logged in to this store
        shopify theme list -e production | Out-Null
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
    if (git remote) { git pull; Check "git pull" }

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
    if (-not $Message) { $Message = "Update $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    Info "Committing and pushing to git (Shopify not touched)..."
    Commit-And-Push $Message
    Ok "Saved to git."
}

function Show-Help {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 10 | ForEach-Object { $_ -replace '^#\s?', '' }
}

switch ($Action) {
    "install" { Do-Install }
    "pull"    { Do-Pull }
    "push"    { Do-Push }
    "deploy"  { Do-Deploy }
    default   { Show-Help }
}
