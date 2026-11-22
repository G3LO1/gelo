# Installs the roblox-studio skills (with the /gelo router) into a project's .claude\skills\ folder
# (or ~\.claude\skills\ with -Global), so Claude Code picks them up there without the plugin.
# -For agents puts them in .agents\skills\ instead, the shared Agent Skills folder read by Codex, ChatGPT desktop,
# Gemini CLI, Cursor and others; -For all does both.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                    -> current folder (.\.claude\skills\)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Project "D:\Game" -> that project
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Global            -> every project (~\.claude\skills\)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -For agents       -> .\.agents\skills\ (Codex, ChatGPT desktop, ...)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -For all          -> both
#
# Without a checkout:
#   irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1))) -Global
#
# $env:GELO_REF picks a branch or tag to download (default main); $env:GELO_ZIP_URL overrides the whole URL.
param(
  [string]$Project = "",
  [switch]$Global,
  [ValidateSet("claude", "agents", "all")]
  [string]$For = "claude"
)

$ErrorActionPreference = "Stop"

if ($Global -and $Project) { throw "Use either -Global or -Project, not both" }

if ($Global) {
  $base = $HOME
} else {
  if (-not $Project) { $Project = (Get-Location).Path }
  if (-not (Test-Path -PathType Container $Project)) { throw "Folder $Project does not exist" }
  $base = (Resolve-Path $Project).Path
}
$dirs = switch ($For) { "claude" { @(".claude") } "agents" { @(".agents") } "all" { @(".claude", ".agents") } }

# Skills from this checkout, or from a downloaded archive when the script was piped in.
$src = $null
$tmp = $null
if ($PSScriptRoot) {
  $candidate = Join-Path $PSScriptRoot (Join-Path "plugins" (Join-Path "roblox-studio" "skills"))
  if (Test-Path -PathType Container $candidate) { $src = $candidate }
}

try {
  if (-not $src) {
    $ref = if ($env:GELO_REF) { $env:GELO_REF } else { "main" }
    $url = if ($env:GELO_ZIP_URL) { $env:GELO_ZIP_URL } else { "https://codeload.github.com/G3LO1/gelo/zip/$ref" }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gelo-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "gelo.zip"
    Write-Host "Downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $found = Get-ChildItem -Path $tmp -Directory | ForEach-Object {
      Join-Path $_.FullName (Join-Path "plugins" (Join-Path "roblox-studio" "skills"))
    } | Where-Object { Test-Path -PathType Container $_ } | Select-Object -First 1
    if (-not $found) { throw "plugins/roblox-studio/skills not found in $url" }
    $src = $found
  }

  foreach ($d in $dirs) {
    # Windows paths everywhere, but keep it working under pwsh on macOS/Linux too.
    $target = (Join-Path $base (Join-Path $d "skills")) -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $count = 0
    foreach ($dir in Get-ChildItem -Path $src -Directory) {
      if (-not (Test-Path (Join-Path $dir.FullName "SKILL.md"))) { continue }
      # Replace only our own skills; anything else in the folder stays.
      $dest = Join-Path $target $dir.Name
      if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
      Copy-Item -Recurse -Force $dir.FullName $dest
      Write-Host "  $($dir.Name)"
      $count++
    }
    if ($count -eq 0) { throw "No skills found in $src" }
    Write-Host "OK: $count skills installed in $target"
    if ($d -eq ".claude") {
      Write-Host "Claude Code: start a new session there and type /gelo (or e.g. /roblox-map-builder)"
    } else {
      Write-Host "Codex: `$gelo, ChatGPT desktop: @gelo, Gemini CLI / Cursor / others: ask for gelo (restart the tool first)"
    }
  }
} finally {
  if ($tmp -and (Test-Path $tmp)) { Remove-Item -Recurse -Force $tmp }
}
