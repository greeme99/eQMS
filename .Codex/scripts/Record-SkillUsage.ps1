[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Name)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$usagePath = Join-Path $root '.Codex\skills\.usage.json'
function Assert-NoReparseChain([string]$Base, [string]$Candidate) {
  $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\','/')
  $candidateFull = [IO.Path]::GetFullPath($Candidate)
  $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
  if (-not $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes project root.' }
  $current = $baseFull
  foreach ($segment in ($candidateFull.Substring($baseFull.Length).TrimStart('\','/') -split '[\\/]')) {
    if (-not $segment) { continue }
    $current = Join-Path $current $segment
    if (Test-Path -LiteralPath $current) {
      if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse points are not allowed: $current" }
    } else { break }
  }
}
Assert-NoReparseChain $root $usagePath
$usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = $usage.PSObject.Properties[$Name]
if (-not $entry) { throw "Unknown skill: $Name" }
if ($entry.Value.state -eq 'archived') { throw "Archived skill cannot be recorded as used: $Name" }
$entry.Value.use_count = [int]$entry.Value.use_count + 1
$entry.Value.last_used_at = (Get-Date).ToUniversalTime().ToString('o')
$entry.Value.state = 'active'
Assert-NoReparseChain $root $usagePath
$usage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $usagePath -Encoding UTF8
Write-Host "Recorded usage: $Name"
