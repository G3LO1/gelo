# Installs the roblox-studio skills into a project's .claude\skills\ folder (or ~\.claude\skills\ with -Global),
# so Claude Code picks them up there without the plugin.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                    -> current folder (.\.claude\skills\)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Project "D:\Game" -> that project
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Global            -> every project (~\.claude\skills\)
#
# Without a checkout:
#   irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1))) -Global
#
# $env:GELO_REF picks a branch or tag to download (default main); $env:GELO_ZIP_URL overrides the whole URL.
param(
  [string]$Project = "",
  [switch]$Global
)

$ErrorActionPreference = "Stop"

if ($Global -and $Project) { throw "Use either -Global or -Project, not both" }

if ($Global) {
  $target = Join-Path $HOME ".claude\skills"
} else {
  if (-not $Project) { $Project = (Get-Location).Path }
  if (-not (Test-Path -PathType Container $Project)) { throw "Folder $Project does not exist" }
  $target = Join-Path (Resolve-Path $Project).Path ".claude\skills"
}
# Windows paths everywhere, but keep it working under pwsh on macOS/Linux too.
$target = $target -replace '[\\/]', [IO.Path]::DirectorySeparatorChar

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
  Write-Host "Restart Claude Code in that folder (or start a new session) and type e.g. /roblox-map-builder"
} finally {
  if ($tmp -and (Test-Path $tmp)) { Remove-Item -Recurse -Force $tmp }
}
