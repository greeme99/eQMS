[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$DraftPath,
  [Parameter(Mandatory=$true)][ValidateSet('Approve','Reject')][string]$Decision
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$draft = if ([IO.Path]::IsPathRooted($DraftPath)) {
  [IO.Path]::GetFullPath($DraftPath)
} else {
  [IO.Path]::GetFullPath((Join-Path (Get-Location) $DraftPath))
}
$allowedRoots = @(
  [IO.Path]::GetFullPath((Join-Path $root 'memory\pending')),
  [IO.Path]::GetFullPath((Join-Path $root '.Codex\memory\pending')),
  [IO.Path]::GetFullPath((Join-Path $root '.Codex\skills\pending'))
)
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
Assert-NoReparseChain $root $draft
if ([IO.Path]::GetExtension($draft) -ne '.md') { throw 'DraftPath must be a Markdown file.' }
$parent = [IO.Path]::GetDirectoryName($draft)
$approvedRoot = $allowedRoots | Where-Object { $parent.Equals($_, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
if (-not $approvedRoot) { throw 'DraftPath must be a direct child of an approved pending directory.' }
if (-not (Test-Path -LiteralPath $draft -PathType Leaf)) { throw 'Draft does not exist.' }
if ([IO.Path]::GetFileName($draft) -eq 'README.md') { throw 'README.md is not a learning draft.' }
$rootItem = Get-Item -LiteralPath $approvedRoot -Force
$draftItem = Get-Item -LiteralPath $draft -Force
if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($draftItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw 'Reparse points are not allowed for pending roots or drafts.'
}

if ($Decision -eq 'Reject') {
  if ($PSCmdlet.ShouldProcess($draft, 'Reject and remove pending draft')) { Remove-Item -LiteralPath $draft }
  if ($WhatIfPreference) { Write-Host 'Draft rejection validated (WhatIf).' } else { Write-Host 'Draft rejected.' }
  exit 0
}

$raw = Get-Content -LiteralPath $draft -Raw -Encoding UTF8
$draftMatch = [regex]::Match($raw, '(?ms)\A(?<header>.*?)^---\s*\r?\n(?<body>.*)\r?\n^---\s*\r?\nreason:\s*(?<reason>.*)\z')
if (-not $draftMatch.Success) { throw 'Draft must contain header, --- body ---, and reason.' }
$header = @{}
$allowedHeaderKeys = @('target','action','old_text','skill_name')
foreach ($line in ($draftMatch.Groups['header'].Value -split "`r?`n")) {
  if (-not $line.Trim()) { continue }
  if ($line -notmatch '^([a-z_]+):\s*(.*)$') { throw "Invalid header line: $line" }
  $key = $matches[1]
  if ($key -notin $allowedHeaderKeys) { throw "Unknown header key: $key" }
  if ($header.ContainsKey($key)) { throw "Duplicate header key: $key" }
  $header[$key] = $matches[2].Trim()
}
$body = $draftMatch.Groups['body'].Value.Trim()
$reason = $draftMatch.Groups['reason'].Value.Trim()
if (-not $header.target -or -not $header.action) { throw 'Draft requires target and action.' }
if (-not $reason) { throw 'Draft requires a non-empty reason.' }

if ($header.target -eq 'skill') {
  if ($header.skill_name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw 'Invalid skill_name.' }
  if ($header.action -notin @('create','patch')) { throw 'Skill action must be create or patch.' }
  if (-not $body) { throw 'Skill draft body must not be empty.' }
  $skillDir = Join-Path $root ('.Codex\skills\' + $header.skill_name)
  $skillPath = Join-Path $skillDir 'SKILL.md'
  $usagePath = Join-Path $root '.Codex\skills\.usage.json'
  Assert-NoReparseChain $root $skillDir
  Assert-NoReparseChain $root $skillPath
  Assert-NoReparseChain $root $usagePath
  if ($header.action -eq 'create') {
    if (Test-Path -LiteralPath $skillDir) { throw 'Skill already exists.' }
    foreach ($marker in @('---','name:','description:','## When to Use','## Procedure','## Pitfalls','## Verification')) {
      if (-not $body.Contains($marker)) { throw "Skill draft missing: $marker" }
    }
    $frontmatterName = [regex]::Match($body, '(?m)^name:\s*([^\r\n]+)\s*$')
    if (-not $frontmatterName.Success -or $frontmatterName.Groups[1].Value.Trim() -ne $header.skill_name) {
      throw 'Skill frontmatter name must match skill_name.'
    }
    $usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($usage.PSObject.Properties[$header.skill_name]) { throw 'Skill usage metadata already exists.' }
    if ($PSCmdlet.ShouldProcess($skillPath, 'Create approved skill')) {
      Assert-NoReparseChain $root $skillDir
      Assert-NoReparseChain $root $usagePath
      New-Item -ItemType Directory -Path $skillDir | Out-Null
      Set-Content -LiteralPath $skillPath -Value $body -Encoding UTF8
      $now = (Get-Date).ToUniversalTime().ToString('o')
      $entry = [pscustomobject]@{ use_count=0; last_used_at=$null; patch_count=0; last_patched_at=$null; created_at=$now; state='active'; pinned=$false; created_by='agent' }
      $usage | Add-Member -NotePropertyName $header.skill_name -NotePropertyValue $entry
      $usage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $usagePath -Encoding UTF8
    }
  } else {
    if (-not (Test-Path -LiteralPath $skillPath)) { throw 'Skill does not exist.' }
    if (-not $header.old_text) { throw 'patch requires old_text.' }
    $current = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
    if (($current.Split(@($header.old_text), [StringSplitOptions]::None).Count - 1) -ne 1) { throw 'old_text must occur exactly once.' }
    $usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = $usage.PSObject.Properties[$header.skill_name]
    if (-not $entry) { throw 'Skill usage metadata does not exist.' }
    if ($PSCmdlet.ShouldProcess($skillPath, 'Patch approved skill')) {
      Assert-NoReparseChain $root $skillPath
      Assert-NoReparseChain $root $usagePath
      Set-Content -LiteralPath $skillPath -Value $current.Replace($header.old_text, $body) -Encoding UTF8
      $entry.Value.patch_count = [int]$entry.Value.patch_count + 1
      $entry.Value.last_patched_at = (Get-Date).ToUniversalTime().ToString('o')
      $usage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $usagePath -Encoding UTF8
    }
  }
} else {
  $targets = @{ 'memory'='memory\MEMORY.md'; 'user'='memory\USER.md'; 'project-memory'='.Codex\memory\MEMORY.md' }
  if (-not $targets.ContainsKey($header.target)) { throw 'Invalid memory target.' }
  if ($header.action -notin @('add','replace','remove')) { throw 'Invalid memory action.' }
  if ($header.action -ne 'remove' -and -not $body) { throw 'Memory draft body must not be empty.' }
  $targetPath = Join-Path $root $targets[$header.target]
  $configPath = Join-Path $root '.Codex\learning-loop.json'
  Assert-NoReparseChain $root $targetPath
  Assert-NoReparseChain $root $configPath
  $current = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8
  if ($header.action -eq 'add') { $next = $current.TrimEnd() + "`r`n" + $body + "`r`n" }
  else {
    if (-not $header.old_text) { throw "$($header.action) requires old_text." }
    if (($current.Split(@($header.old_text), [StringSplitOptions]::None).Count - 1) -ne 1) { throw 'old_text must occur exactly once.' }
    $replacement = if ($header.action -eq 'replace') { $body } else { '' }
    $next = $current.Replace($header.old_text, $replacement)
  }
  $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $limit = if ($header.target -eq 'user') { $config.user_max_chars } else { $config.memory_max_chars }
  if ($next.Length -gt $limit) { throw "Approved content would exceed limit: $limit characters." }
  if ($PSCmdlet.ShouldProcess($targetPath, 'Apply approved memory draft')) {
    Assert-NoReparseChain $root $targetPath
    Set-Content -LiteralPath $targetPath -Value $next -Encoding UTF8
  }
}

if ($PSCmdlet.ShouldProcess($draft, 'Remove resolved pending draft')) {
  Assert-NoReparseChain $root $draft
  Remove-Item -LiteralPath $draft
}
if ($WhatIfPreference) { Write-Host 'Draft approval validated (WhatIf).' } else { Write-Host 'Draft approved and applied.' }
