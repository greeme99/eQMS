# Skill Pending

재사용 가치와 검증 근거가 있는 절차의 미승인 초안을 둔다.

```text
target: skill
action: create | patch
skill_name: lowercase-hyphen-slug
old_text: patch 대상 문자열
---
create면 완전한 SKILL.md, patch면 교체할 문자열
---
reason: 재사용 근거와 성공한 검증
```

승인 후 `Resolve-LearningDraft.ps1`로 반영한다. `patch`는 정확히 한 번 나타나는 `old_text`만 교체한다.
