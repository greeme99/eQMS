[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$required = @(
  'AGENTS.md', 'GROWING-AGENT.md', 'memory\MEMORY.md', 'memory\USER.md',
  'memory\pending\README.md', '.Codex\memory\MEMORY.md',
  '.Codex\skills\.usage.json', '.Codex\learning-loop.json',
  '.Codex\scripts\Resolve-LearningDraft.ps1',
  '.Codex\scripts\Record-SkillUsage.ps1', '.Codex\scripts\Invoke-Curator.ps1',
  '.Codex\skills\project-workflow\SKILL.md',
  '.Codex\skills\ponytail\SKILL.md', '.Codex\skills\ponytail-review\SKILL.md',
  '.Codex\skills\pending\README.md', '.Codex\skills\.archive'
)
$errors = New-Object System.Collections.Generic.List[string]

foreach ($relative in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
    $errors.Add("Missing: $relative")
  }
}

try { $config = Get-Content -LiteralPath (Join-Path $root '.Codex\learning-loop.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Invalid learning-loop.json: $($_.Exception.Message)") }
try { $usage = Get-Content -LiteralPath (Join-Path $root '.Codex\skills\.usage.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Invalid .usage.json: $($_.Exception.Message)") }

if ($config) {
  if ($config.stale_after_days -ge $config.archive_after_days) { $errors.Add('stale_after_days must be less than archive_after_days') }
  $memoryLength = (Get-Content -LiteralPath (Join-Path $root 'memory\MEMORY.md') -Raw -Encoding UTF8).Length
  $projectLength = (Get-Content -LiteralPath (Join-Path $root '.Codex\memory\MEMORY.md') -Raw -Encoding UTF8).Length
  $userLength = (Get-Content -LiteralPath (Join-Path $root 'memory\USER.md') -Raw -Encoding UTF8).Length
  if ($memoryLength -gt $config.memory_max_chars) { $errors.Add('memory/MEMORY.md exceeds memory_max_chars') }
  if ($projectLength -gt $config.memory_max_chars) { $errors.Add('.Codex/memory/MEMORY.md exceeds memory_max_chars') }
  if ($userLength -gt $config.user_max_chars) { $errors.Add('memory/USER.md exceeds user_max_chars') }
}

$skillPath = Join-Path $root '.Codex\skills\project-workflow\SKILL.md'
if (Test-Path -LiteralPath $skillPath) {
  $skill = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
  foreach ($marker in @('---', 'name:', 'description:', '## When to Use', '## Procedure', '## Pitfalls', '## Verification')) {
    if (-not $skill.Contains($marker)) { $errors.Add("project-workflow missing: $marker") }
  }
}

if ($usage) {
  foreach ($requiredSkill in @('project-workflow','ponytail','ponytail-review')) {
    if (-not $usage.PSObject.Properties[$requiredSkill]) { $errors.Add("usage missing template skill: $requiredSkill") }
  }
  foreach ($property in $usage.PSObject.Properties) {
    if ($property.Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $errors.Add("unsafe usage key: $($property.Name)") }
    foreach ($field in @('use_count','last_used_at','patch_count','state','pinned','created_by')) {
      if (-not $property.Value.PSObject.Properties[$field]) { $errors.Add("usage $($property.Name) missing $field") }
    }
    $expected = if ($property.Value.state -eq 'archived') {
      Join-Path $root ('.Codex\skills\.archive\' + $property.Name)
    } else {
      Join-Path $root ('.Codex\skills\' + $property.Name)
    }
    if (-not (Test-Path -LiteralPath $expected -PathType Container)) { $errors.Add("usage directory mismatch: $($property.Name)") }
  }
}

if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_ }
  exit 1
}
Write-Host 'Learning loop validation passed.' -ForegroundColor Green
