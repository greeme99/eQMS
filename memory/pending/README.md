# Memory Pending

`grow`가 만든 미승인 memory 초안을 둔다. 승인 전 canonical memory를 수정하지 않는다.

```text
target: memory | user | project-memory
action: add | replace | remove
old_text: replace/remove 대상 문자열
---
추가하거나 교체할 내용
---
reason: 저장 근거와 검증 방법
```

`add`는 `old_text`가 없어도 된다. 한 사실은 한 저장소에만 둔다.
