# Growing Agent Operations

이 프로젝트는 bounded memory, on-demand skill, pending 승인 게이트, usage tracking, reversible archive로 구성된 폐쇄형 학습루프를 사용한다.

```powershell
# 구조 검증
powershell -NoProfile -ExecutionPolicy Bypass -File .\.Codex\scripts\Test-LearningLoop.ps1

# pending 승인/거절
powershell -NoProfile -ExecutionPolicy Bypass -File .\.Codex\scripts\Resolve-LearningDraft.ps1 -DraftPath <draft.md> -Decision Approve

# skill 사용 기록
powershell -NoProfile -ExecutionPolicy Bypass -File .\.Codex\scripts\Record-SkillUsage.ps1 -Name <skill-name>

# curator dry-run / apply
powershell -NoProfile -ExecutionPolicy Bypass -File .\.Codex\scripts\Invoke-Curator.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\.Codex\scripts\Invoke-Curator.ps1 -Apply
```

승인 전 canonical memory/skill을 학습 목적으로 직접 고치지 않는다. Archive는 삭제가 아니며 원래 skill 위치로 되돌리고 metadata state를 `active`로 바꾸면 복구할 수 있다.
