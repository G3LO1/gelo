# Installs the roblox-studio skills into a project's .claude\skills\ folder (or ~\.claude\skills\ with -Global),
# so Claude Code picks them up there without the plugin. Run it from a clone of the repo:
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                    -> current folder (.\.claude\skills\)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Project "D:\Game" -> that project
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Global            -> every project (~\.claude\skills\)
param(
  [string]$Project = "",
  [switch]$Global
)

$ErrorActionPreference = "Stop"

if ($Global -and $Project) { throw "Use either -Global or -Project, not both" }

$src = $null
if ($PSScriptRoot) {
  $src = Join-Path $PSScriptRoot (Join-Path "plugins" (Join-Path "roblox-studio" "skills"))
}
if (-not $src -or -not (Test-Path -PathType Container $src)) {
  throw "Run install.ps1 from a clone of the repo: git clone https://github.com/G3LO1/gelo.git, then powershell -ExecutionPolicy Bypass -File gelo\install.ps1 -Project ""D:\Game"""
}

if ($Global) {
  $target = Join-Path $HOME ".claude\skills"
} else {
  if (-not $Project) { $Project = (Get-Location).Path }
  if (-not (Test-Path -PathType Container $Project)) { throw "Folder $Project does not exist" }
  $target = Join-Path (Resolve-Path $Project).Path ".claude\skills"
}
# Windows paths everywhere, but keep it working under pwsh on macOS/Linux too.
$target = $target -replace '[\\/]', [IO.Path]::DirectorySeparatorChar

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
