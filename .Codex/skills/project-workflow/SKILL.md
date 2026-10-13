---
name: project-workflow
description: eQMS 요구사항·CSV·검증 게이트를 포함한 프로젝트 기본 작업 절차
---

# eQMS Project Workflow

## When to Use

두 단계 이상이거나 파일 변경이 필요한 작업에 사용한다.

## Procedure

1. `memory/MEMORY.md`, `memory/USER.md`, `.Codex/memory/MEMORY.md`, pending 초안을 읽는다.
2. `Research/`와 `plan.md`에서 목표·범위·제약·완료조건·요구사항 ID를 확인한다.
3. URS → 위험평가 → 설계/구현 → 시험증적 → RTM → CSV 산출물 연결을 계획한다.
4. 최소 변경으로 구현하고 관련 단위·통합·보안·데이터 무결성 시험을 실행한다.
5. 규제 변경·전자서명·감사추적·RAG 권한 경계는 별도 검토 항목으로 남긴다.
6. 재사용 가치가 확인된 내용만 pending 초안에 기록하며, 사용자 승인 전 canonical memory/skill을 직접 학습시키지 않는다.

## Pitfalls

- 내부 Research의 코드 예시를 검증된 규제 적합성으로 간주하지 않는다.
- MVP와 최종 검증 범위를 섞지 않는다.
- 전역 설정과 Claude 소유 파일을 수정하지 않는다.

## Verification

`pwsh -NoProfile -File ./.Codex/scripts/Test-LearningLoop.ps1`가 통과해야 하며, 기능 변경은 `plan.md`의 관련 `TC-*`를 실행하거나 미실행 사유를 기록한다.
