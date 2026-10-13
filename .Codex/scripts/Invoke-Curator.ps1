[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$configPath = Join-Path $root '.Codex\learning-loop.json'
$usagePath = Join-Path $root '.Codex\skills\.usage.json'
$now = (Get-Date).ToUniversalTime()
$changes = New-Object System.Collections.Generic.List[string]

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
Assert-NoReparseChain $root $configPath
Assert-NoReparseChain $root $usagePath
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($property in $usage.PSObject.Properties) {
  $name = $property.Name
  $entry = $property.Value
  if ($name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Unsafe skill metadata key: $name" }
  if ($entry.created_by -ne 'agent' -or [bool]$entry.pinned -or $entry.state -eq 'archived') { continue }
  $basis = if ($entry.last_used_at) { $entry.last_used_at } else { $entry.created_at }
  if (-not $basis) { throw "Skill has no lifecycle timestamp: $name" }
  try { $basisTime = ([datetime]$basis).ToUniversalTime() } catch { throw "Invalid lifecycle timestamp for skill: $name" }
  $days = [math]::Floor(($now - $basisTime).TotalDays)
  if ($days -ge [int]$config.archive_after_days) {
    $changes.Add("ARCHIVE $name ($days days idle)")
    if ($Apply -and $entry.state -ne 'archived') {
      $source = Join-Path $root ('.Codex\skills\' + $name)
      $destination = Join-Path $root ('.Codex\skills\.archive\' + $name)
      $skillsRoot = [IO.Path]::GetFullPath((Join-Path $root '.Codex\skills'))
      $archiveRoot = [IO.Path]::GetFullPath((Join-Path $skillsRoot '.archive'))
      $source = [IO.Path]::GetFullPath($source)
      $destination = [IO.Path]::GetFullPath($destination)
      Assert-NoReparseChain $root $source
      Assert-NoReparseChain $root $destination
      if (-not ([IO.Path]::GetDirectoryName($source).Equals($skillsRoot, [StringComparison]::OrdinalIgnoreCase))) { throw "Unsafe skill source: $name" }
      if (-not ([IO.Path]::GetDirectoryName($destination).Equals($archiveRoot, [StringComparison]::OrdinalIgnoreCase))) { throw "Unsafe archive destination: $name" }
      if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Skill directory missing: $name" }
      if ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse-point skill cannot be archived: $name" }
      if (Test-Path -LiteralPath $destination) { throw "Archive destination already exists: $name" }
      Move-Item -LiteralPath $source -Destination $destination
      $entry.state = 'archived'
      if (-not $entry.PSObject.Properties['archived_at']) { $entry | Add-Member -NotePropertyName archived_at -NotePropertyValue $now.ToString('o') }
      else { $entry.archived_at = $now.ToString('o') }
    }
  } elseif ($days -ge [int]$config.stale_after_days) {
    $changes.Add("STALE $name ($days days idle)")
    if ($Apply -and $entry.state -eq 'active') { $entry.state = 'stale' }
  }
}

if ($changes.Count -eq 0) { Write-Host 'No curator transitions.' }
else { $changes | ForEach-Object { Write-Host $_ } }

if ($Apply) {
  Assert-NoReparseChain $root $usagePath
  $usage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $usagePath -Encoding UTF8
  $reportDir = Join-Path $root '.Codex\reports'
  Assert-NoReparseChain $root $reportDir
  New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
  $reportPath = Join-Path $reportDir ('curator-' + $now.ToString('yyyyMMdd-HHmmss') + '.md')
  Assert-NoReparseChain $root $reportPath
  $lines = @('# Curator Report', '', ('Run: ' + $now.ToString('o')), '')
  if ($changes.Count -eq 0) { $lines += '- No transitions.' } else { $lines += ($changes | ForEach-Object { '- ' + $_ }) }
  Assert-NoReparseChain $root $reportPath
  Set-Content -LiteralPath $reportPath -Value $lines -Encoding UTF8
  Write-Host "Applied reversible transitions. Report: $reportPath"
} else {
  Write-Host 'Dry-run only. Pass -Apply to update state and move archived skills.'
}
