# 의료기기 품질·GMP 관리 시스템(Medical eQMS) 구축 종합계획서

| 항목 | 내용 |
|---|---|
| 문서번호 | PLAN-EQMS-001 |
| 버전 | **2.0 (근거 검증 반영본)** |
| 작성일 | 2026-10-11 |
| 대상 시스템 | Medical eQMS (의료기기 품질·GMP 통합관리 시스템) |
| 배포 형태 | On-Premise (사내 AX 서버) |
| GAMP 분류 | Category 4(설정형) + Category 5(커스텀) 혼합 — 모듈별 분류표는 §8.2 |
| 1차 근거 | G-Research.md, P-eQMS-01 ~ P-eQMS-10 (사내 조사자료) |
| 2차 근거 | eCFR, FDA, EU DSS, Haystack, MinIO 공식 문서 (2026-10-11 직접 확인) |

> **v2.0 개정 사유**: v1.0은 사내 조사자료만을 근거로 작성되었으나, 공식 1차 출처 검증 결과 **규제 조문 번호 3건, 구현 코드 사양 4건, 모델 선정 1건의 중대 오류**가 확인되어 전면 수정함. 수정 내역은 §0에 전량 기재한다.

> **약어**: eQMS(Electronic Quality Management System) / GMP(Good Manufacturing Practice) / QMSR(Quality Management System Regulation) / CSV(Computer System Validation) / CSA(Computer Software Assurance) / GPSV(General Principles of Software Validation) / URS(User Requirements Specification) / RTM(Requirements Traceability Matrix) / VMP(Validation Master Plan) / VSR(Validation Summary Report) / IQ·OQ·PQ(Installation·Operational·Performance Qualification) / CAPA(Corrective And Preventive Action) / NC(Nonconformance) / MDF(Medical Device File) / DHF·DMR·DHR(Design History File·Device Master Record·Device History Record) / PAdES(PDF Advanced Electronic Signatures) / DTBS(Data To Be Signed) / DSS(Digital Signature Service) / RAG(Retrieval-Augmented Generation) / WORM(Write Once Read Many) / RBAC(Role-Based Access Control) / UDI-DI(Unique Device Identifier - Device Identifier) / NTP(Network Time Protocol)

---

## Executive Summary

최소 투자로 규제 준수형 eQMS를 확보하는 경로는 **"오픈소스 운영기반(Odoo·Nextcloud) + 자체 개발 규제통제 계층(FastAPI·PostgreSQL)"의 이원 구조**이며, 4주 MVP(감사추적·문서버전·전자서명·RAG) 확보 후 CAPA·교육·설계추적성·CSV 패키지를 순차 확장한다.

검증 결과 **검증 전략의 기준을 CSV에서 CSA로 전환**한다. FDA는 2025-09-24 「Computer Software Assurance for Production and Quality System Software」 최종 가이던스를 발행하고 2026-02-03 QMSR 정렬판으로 개정했으며, 이는 GPSV Section 6을 대체한다. 고위험 기능은 scripted test, 저위험 기능은 unscripted test로 차등 적용하여 **문서 작업량을 줄이되 위험 판단 근거를 감사 가능한 형태로 문서화**하는 것이 핵심이다.

**총 구축 기간**: 약 12개월 (MVP 4주 + 확장 6단계)
**최대 리스크**: 오픈소스 eQMS의 감사기관 수용 여부 → CSA 기반 위험평가 + IQ/OQ/PQ 증적으로 대응

---

## 0. 근거 검증 결과 및 v1.0 대비 수정 사항

본 절은 **원본 조사자료(P-eQMS-01~10)를 그대로 구현할 경우 발생하는 오류**를 공식 1차 출처로 검증한 결과다. 개발 착수 전 반드시 숙지한다.

### 0.1 규제 오류 (심각도: 치명 — 감사 지적 직결)

| # | 원본 기술 | 검증 결과 | 1차 출처 |
|---|---|---|---|
| R-1 | "FDA QMSR: 설계관리 820.30, CAPA 820.100, 생산관리 820.70, 기록 820.180" | **전부 [Reserved] 처리되어 현존하지 않음.** 현행 Part 820은 820.1(Scope), 820.3(Definitions), 820.7(Incorporation by reference), 820.10(Requirements for a QMS), 820.35(Control of records), 820.45(Device labeling and packaging controls) **6개 조문뿐**이며 Subparts C–O는 전부 Reserved | eCFR 21 CFR Part 820 (2026-10-07 기준) |
| R-2 | QMSR 시행 사실만 기재 | 2026-02-02 시행과 **동시에 FDA는 QSIT 사용을 중단**하고 Compliance Program 7382.850 기반 신규 사찰 프로세스를 적용. **경영검토·내부감사·공급업체 감사보고서가 FDA 조사 대상으로 편입** (구 820.180(c) 면제 폐지) | FDA QMSR FAQ, FDA 교육자료(2026-04) |
| R-3 | CSA를 "2025년 가이던스" 수준으로만 언급 | CSA 최종본 **2025-09-24 발행**, **2026-02-03 QMSR 명칭 정렬 개정판** 발행. GPSV Section 6을 **대체(supersede)**. 검증 전략의 1차 기준 문서임 | FDA / Federal Register 90 FR 45945 |
| R-4 | Part 11 요구사항을 감사추적·전자서명 2개로만 정의 | **11.200(a)(1) 2요소 서명, 11.300 ID/비밀번호 통제, 11.100(c) FDA 비부인 서한 제출, 11.10(b) 사람이 읽을 수 있는 사본 + 전자 사본 제공, 11.10(f) 단계 순서 강제, 11.10(k)(2) 시스템 문서 변경통제**가 URS에서 누락 | eCFR 21 CFR Part 11 |

### 0.2 구현 오류 (심각도: 치명 — 코드가 동작하지 않음)

| # | 원본 코드 | 검증 결과 | 1차 출처 |
|---|---|---|---|
| I-1 | `POST /services/rest/signature/one-document/signDocument`에 multipart로 `keyAlias`·`keystorePassword` 전송 (1-step) | **동작하지 않음.** DSS 서명은 **JSON 기반 3-step 상태 비저장 프로세스**: ① `getDataToSign` → ② 키로 DTBS 서명(서버 서명은 별도 server-signing 서비스) → ③ `signDocument`. 두 호출의 파라미터, **특히 `blevelParams.signingDate`(epoch ms)가 완전히 동일**해야 함 | DSS Cookbook `webservices.adoc`, `_restdocs/sign-and-extend-one-document/1,2` |
| I-2 | `validation_result.get("valid", False)` | **해당 키 없음 → 항상 False → 모든 서명이 검증 실패 처리됨.** 실제 경로: `SimpleReport.signatureOrTimestampOrEvidenceRecord[0].Signature.Indication` ∈ {`TOTAL_PASSED`, `INDETERMINATE`, `TOTAL_FAILED`} + `SubIndication`. 엔드포인트도 `validateDocument`가 아닌 **`/services/rest/validation/validateSignature`** | DSS `_restdocs/validate-doc/1` 요청·응답 샘플 |
| I-3 | DSS 서명 검증 시 trust anchor 미고려 | 사내 CA를 DSS 신뢰 목록에 등록하지 않으면 `INDETERMINATE / NO_CERTIFICATE_CHAIN_FOUND`로 판정됨 (DSS 공식 샘플 응답에서 재현됨) | 동일 |
| I-4 | `PromptBuilder` → `OllamaChatGenerator` 연결, `replies[0].content` | **타입 불일치로 파이프라인 연결 실패.** `OllamaChatGenerator`는 `List[ChatMessage]`를 받으므로 `ChatPromptBuilder`를 써야 함. 또한 `ChatMessage.content`는 **Haystack 2.9에서 제거**되어 `.text` 사용 | Haystack 공식 문서 (ChatMessage / OllamaChatGenerator) |
| I-5 | `BAAI/bge-small-en-v1.5`, `embedding_dim=384`로 한글 SOP 색인 | **영어 전용 모델(384차원, 512 토큰).** 한글 문서 검색 품질이 확보되지 않음. → `BAAI/bge-m3`(**1024차원**, 8192 토큰, 100개 언어, MIT) 또는 `dragonkue/BGE-m3-ko`(1024차원, Apache-2.0)로 교체. Qdrant `embedding_dim`도 1024로 변경 필수 | BAAI 모델카드 / NVIDIA·Zilliz 모델 사양표 |

### 0.3 설계 결함 (심각도: 높음 — 동작하나 규제 요건 미충족)

| # | 원본 설계 | 검증 결과 및 대응 |
|---|---|---|
| D-1 | 감사추적 불변성을 `CREATE RULE ... DO INSTEAD NOTHING`으로 구현 | RULE 방식은 변경 시도를 **조용히 무시**하므로 OQ-AT-002의 "차단 확인" 증적을 만들 수 없음. → **예외를 발생시키는 BEFORE UPDATE OR DELETE 트리거**로 통일 (§5.2) |
| D-2 | MinIO WORM만으로 원본 보호 | **Object Lock은 버전 미지정 DELETE를 막지 못하고 Delete Marker를 생성**하여 객체가 숨겨짐. 하위 버전은 보호되나 조회상 "삭제"로 보임. → IAM 정책에서 `s3:DeleteObject` 자체를 금지하고, **COMPLIANCE 모드 + 버전관리**를 버킷 생성 시 동시 활성화 (§7.2) |
| D-3 | RAG 접근제어를 `{"field":"meta.access_roles","operator":"in","value":user.roles}` 하나로 처리 | Haystack 공식 문서상 **사용 가능 연산자는 Document Store 구현에 따라 다름.** 배열 payload에 대한 `in` 동작은 저장소 의존적이므로, **OQ 음성 테스트(권한 없는 역할로 비공개 문서 미검색 확인)를 필수화**하고 애플리케이션 계층에서 2차 재필터링 (방어적 이중화) |
| D-4 | 서명 의미를 `signatureMeaning` 임의 파라미터로 전달 | DSS/PAdES 표준 필드가 아님. → **`commitmentTypeIndications`**(ETSI 표준 서명 약정 유형) + **`imageParameters`**(가시 서명란에 서명자명·일시 표기, Part 11 §11.50(b) "human readable form" 충족) 사용 |
| D-5 | 청킹 `split_by="word", split_length=300` | 한국어는 공백 기준 어절 분할이라 의미 단위가 깨짐. → `split_by="sentence"` 기반 + 토큰 기준 상한 병행, PQ-003에서 Hit@5로 검증 후 확정 |
| D-6 | 시간 기록을 DB 서버 시계에만 의존 | Part 11 §11.10(e)는 "secure, computer-generated, **time-stamped**"를 요구. → 전 구성요소 NTP 동기화 + MinIO는 `MINIO_NTP_SERVER` 설정 (IQ-006에서 검증) |

### 0.4 범위 확정 (v1.0 미해결 항목 해소)

| 항목 | v1.0 상태 | v2.0 결론 |
|---|---|---|
| 국내 KGMP·UDI 연계 | "범위 외, 추가 조사 필요" | **Phase 5에 포함.** 근거: ① 21 CFR 820.10(b)(1)은 ISO 13485 Cl.7.5.8에 대해 **21 CFR Part 830 UDI 부여 체계 문서화**를 요구, ② 820.35(c)는 **기기·배치별 UDI 기록**을 요구, ③ 국내는 의료기기법 시행규칙에 따라 **매월 말일까지 전월 공급내역(공급기관·수량·공급가격)을 의료기기통합정보시스템에 제출** 의무(1~4등급 전면 적용 완료). 설계 결론은 §7.9 |
| DSS의 Part 11 적합성 | "법적 검토 필요" | **"DSS는 서명 기술 제공자이며 Part 11 적합성은 제조사 책임"으로 확정.** DSS/PAdES는 §11.70(서명-기록 결속)과 §11.50(a)(1)(2)를 기술적으로 충족하나, §11.50(a)(3) 서명 의미·§11.100(c) FDA 비부인 서한·§11.200 2요소 인증은 **제조사의 절차와 애플리케이션 구현**으로 충족해야 함 (§7.2) |
| 오픈소스 eQMS 감사 수용성 | "업체 인터뷰 필요" | **쟁점을 재정의.** FDA는 제품의 출처가 아니라 **"의도된 용도에 대한 보증(assurance)"**을 요구하며(CSA 가이던스), 오픈소스/자체개발 여부를 구분하지 않는다. 따라서 수용성은 **CSA 기반 위험평가 + 증적 품질**의 문제이며, 별도 업체 인터뷰 없이 §8 전략으로 대응 가능 |
| 상용 패키지 병행 평가 | 미결 | Phase 0에서 **Build/Buy 판단 게이트**를 명시적 산출물로 설정 (§3.4) |

---

## 1. 목표 및 범위

### 1.1 구축 목표

| # | 목표 | 완료 기준 |
|---|---|---|
| 1 | 규제 준수형 프로세스·워크플로 Backend 구축 | 문서 등록→검토→승인→배포→회수 전 과정 전산화 |
| 2 | 전자서명 연동 및 위·변조 방지 감사추적 | 21 CFR Part 11 Subpart B·C 전 조항 대응 (§2.3) |
| 3 | 이중화 DB 및 무결성 Storage | PostgreSQL Primary/Standby, MinIO Object Lock COMPLIANCE |
| 4 | 제품표준서·설계파일 이력 버전관리 | 구버전 SUPERSEDED, 전 버전 이력 보존, UDI 기록 |
| 5 | 보안형 RAG 기반 품질정보 조회 | 승인 문서만 검색, 출처·버전 100% 인용, 한국어 검색 품질 확보 |
| 6 | On-Premise LLM 품질 AI 비서 | 외부 API 미사용 |
| 7 | 개발/운영 분리 및 CSA 기반 검증 후 운영 전환 | 위험 기반 보증 활동 완료, VSR 승인 |

### 1.2 범위

**포함**: 문서등록·버전관리 / 승인 워크플로 / 감사추적 / PAdES 전자서명 / CAPA / 교육·이수관리 / 설계추적성(RTM) / 설계개발 파일 / MDF / UDI 기록 및 공급내역 보고 데이터 생성 / 승인 SOP RAG / 규제 변경 모니터링

**제외**: ERP 재무연동 / 외부 협력사 포털 / 생산설비 제어 시스템 / 경영 BI / 공급내역의 자동 전송(포털 제출은 수동, §7.9)

### 1.3 전제 조건

- 사내 AX 서버 온프레미스, 소규모~중견(50~300명), 초기 투자 최소화
- 개발(Local) / 검증(Staging) / 운영(AX 서버) 3환경 분리
- 전 서버 NTP 동기화 (Part 11 §11.10(e) 전제)

---

## 2. 규제 요구사항 매핑 (검증본)

### 2.1 현행 21 CFR Part 820 (QMSR) 구조

> **v1.0 수정**: 아래가 2026-10-07 eCFR 기준 **현존하는 전부**다. 구 QSR 조문 번호(820.20~820.250)는 인용하지 않는다.

| 조문 | 제목 | 실질 요구 |
|---|---|---|
| § 820.1 | Scope | 완제품 제조자 적용범위 |
| § 820.3 | Definitions | ISO 13485 + ISO 9000 Cl.3 정의 준용, FD&C Act 정의 우선 |
| § 820.7 | Incorporation by reference | **ISO 13485:2016 및 ISO 9000:2015 Cl.3을 참조로 편입** |
| § 820.10 | Requirements for a QMS | (a) ISO 13485 준수 QMS 문서화 (b) UDI는 **Part 830**, 추적성은 **Part 821**, 보고는 **Part 803**, 시정권고는 **Part 806** (c) **Class II·III 및 소프트웨어 자동화 Class I은 ISO 13485 Cl.7.3 설계개발 준수 필수** (d) 생명유지 기기는 Cl.7.5.9.2 |
| § 820.35 | Control of records | ISO 13485 Cl.4.2.5에 **추가하여** (a) 불만 기록 7개 필수항목 (b) 서비스 기록 6개 필수항목 (c) **기기·배치별 UDI 기록** (d) 기밀표시 |
| § 820.45 | Device labeling and packaging controls | 라벨링·포장 정확성 검사, 릴리스 문서화, 혼입 방지 |

**설계 함의**: 설계관리·CAPA·교육 등의 요건은 이제 **ISO 13485 Clause를 직접 인용**해야 한다. URS의 규제 참조 컬럼은 `21 CFR 820.30` → `ISO 13485 Cl.7.3 (via 21 CFR 820.10(c))` 형식으로 기재한다.

### 2.2 규제별 시스템 매핑

| 규제 | 핵심 요구 | 시스템 기능 |
|---|---|---|
| ISO 13485:2016 Cl.4.2.4/4.2.5 | 문서관리·기록관리 | DMS, 버전관리, Audit Trail |
| ISO 13485 Cl.4.2.3 | Medical Device File | MDF 모듈 |
| ISO 13485 Cl.7.3 (820.10(c)) | 설계개발 | Design and Development File, RTM |
| ISO 13485 Cl.8.5.2/8.5.3 | 시정·예방조치 | CAPA 모듈 |
| ISO 13485 Cl.6.2 | 적격성·교육 | 교육·이수관리 |
| 21 CFR 820.35(c) | 기기·배치별 UDI 기록 | UDI/Lot 기록 모듈 |
| 21 CFR Part 830 | UDI 부여 체계 | UDI-DI 관리 |
| 21 CFR Part 11 | 전자기록·전자서명 | §2.3 전체 |
| FDA CSA 가이던스(2025-09/2026-02) | 위험 기반 소프트웨어 보증 | §8 검증 전략 |
| EU Annex 11 / GAMP 5 2판 | 컴퓨터화 시스템 통제 | CSV 패키지 |
| 의료기기법 시행규칙 | 월별 공급내역 보고 | §7.9 |

### 2.3 21 CFR Part 11 전 조항 대응표 (신규)

> **v1.0 수정**: 원본은 11.10(d)(e), 11.50, 11.70만 다뤘다. 아래가 폐쇄형 시스템에 적용되는 전체다.

| 조항 | 요구사항 | 구현 방식 | 검증 |
|---|---|---|---|
| 11.10(a) | 시스템 밸리데이션 (무효·변조 기록 식별 능력 포함) | CSA 기반 IQ/OQ/PQ + 해시체인 | VSR |
| 11.10(b) | **사람이 읽을 수 있는 사본 + 전자 사본** 생성 및 FDA 제공 | 감사추적 PDF 출력 + CSV/JSON 내보내기 API | OQ-AT-004 |
| 11.10(c) | 보존기간 전체에 걸친 정확·신속 검색 | MinIO 버전관리 + 인덱스 + 백업 | PQ-004 |
| 11.10(d) | 권한자 한정 접근 | Keycloak RBAC | OQ-SEC-001 |
| 11.10(e) | **안전·컴퓨터 생성·시간 기록 감사추적, 이전 기록 은폐 금지, 기록과 동일 기간 보존** | append-only `audit_events` + 트리거 + NTP | OQ-AT-001/002 |
| 11.10(f) | 단계·이벤트 순서 강제 | 상태 전이 규칙 테이블 (§7.1) | OQ-DOC-003 |
| 11.10(g) | 권한 확인(authority check) | 역할별 서명·변경 권한 검사 | OQ-SEC-002 |
| 11.10(h) | 입력 소스 유효성(device check) | 서버 측 입력 검증 | OQ-SEC-003 |
| 11.10(i) | 담당자 교육·경험 확인 | 교육 모듈 + 이수기록 | OQ-TRN-001 |
| 11.10(j) | **전자서명 책임에 관한 문서화된 정책** | SOP-EQMS-003 | 문서 심사 |
| 11.10(k)(1)(2) | **시스템 문서 배포 통제 + 변경 이력 감사추적** | 시스템 문서도 eQMS 내 문서통제 대상에 포함 | OQ-DOC-004 |
| 11.50(a) | 서명자 인쇄명 / 서명 일시 / **서명 의미** | DSS `imageParameters` + `commitmentTypeIndications` + DB 기록 | OQ-SIG-003 |
| 11.50(b) | 위 3항목을 **사람이 읽을 수 있는 형태에 포함** | PDF 가시 서명란에 렌더링 | OQ-SIG-004 |
| 11.70 | 서명-기록 결속(복사·이전 불가) | PAdES 내장 서명 | OQ-SIG-002 |
| 11.100(a)(b) | 서명 유일성, 사전 신원확인 | Keycloak 계정 정책 + HR 신원확인 절차 | 절차 심사 |
| 11.100(c) | **FDA에 비부인 서한(Letter of Non-Repudiation) 제출** | Phase 2 과업으로 등록 (자필서명·서면 제출) | 제출 증빙 |
| 11.200(a)(1)(i)(ii) | **2개 구분 식별요소. 연속 접근 세션 내 첫 서명은 전 요소, 이후 서명은 1개 이상. 세션 외는 매번 전 요소** | 서명 시 ID+비밀번호 재입력, 세션 내 연속 서명은 비밀번호만 재입력하는 로직 구현 | OQ-SIG-005 |
| 11.200(a)(3) | 타인 도용 시 2인 이상 공모 필요 구조 | 비밀번호 비공유 정책 + MFA | 절차 심사 |
| 11.300(a)~(e) | ID/비밀번호 유일성, 주기적 변경·회수, 분실 토큰 관리, 무단사용 즉시 탐지·보고, 장치 주기 시험 | Keycloak 정책 + 실패 로그인 알림 | OQ-SEC-004 |

---

## 3. Build vs Buy 판단

### 3.1 상용 솔루션 벤치마킹 (사내 조사자료 기준)

| 구분 | 솔루션 | 타겟·특징 |
|---|---|---|
| 글로벌 | Greenlight Guru | MedTech 중소기업, 설계통제 강화 |
| | MasterControl | 대기업·중견, ERP/MES 연동 |
| | Qualio | 성장기, 템플릿 기반 빠른 도입 |
| | SimplerQMS | Life Science 전용 사전 밸리데이션, MS 호환 |
| 국내 | GMS-MD (에스지아이시스템) | 의료기기 ERP+GMP, **식약처 통합정보시스템 UDI 직접 연동** |
| | ICUBE G2 / 더존 확장 | ERP + Lot 추적 + KGMP 애드온 |
| | 코아시아·영림원 MES | 설비 연동, eDHR 자동 생성 |
| SaMD | Ketryx / Matrix Req | IEC 62304, SBOM, 요구사항→V&V 추적 |

### 3.2 오픈소스 대안

| 프로젝트 | 라이선스 | 스택 |
|---|---|---|
| QAtrial | AGPL-3.0 | React + Prisma + PostgreSQL |
| OpenQMS | - | Cloud-Native |
| dearauditor-qms-baseline | MIT | Git-native (Issues/PR/Actions) |
| GSTT-CSC QMS Template | - | ISO 13485 SaMD SOP 템플릿 |

> 위 목록은 사내 조사자료(P-eQMS-01) 출처이며, **Phase 0에서 각 저장소의 최신 활동성·라이선스·실제 기능을 직접 확인한 뒤** 채택 여부를 결정한다. AGPL-3.0은 사내 전용 운영 시 공개 의무가 발생하지 않으나, 외부 제공 시 의무가 생기므로 법무 확인이 필요하다.

### 3.3 채택: 하이브리드 자체 구축

| 평가 항목 | Odoo | Nextcloud | FastAPI + PostgreSQL |
|---|---|---|---|
| 주 역할 | ERP·생산·구매·출하 기록 | 문서 저장·공유·버전관리 | **규제 통제 계층** |
| 감사추적 | Part 11 보장 불가 | 별도 검증 필요 | append-only 직접 구현 |
| 전자서명 | 커스텀 필요 | 외부 연동 | DSS PAdES |
| RAG | 별도 | 별도 | Haystack+Qdrant 직접 통합 |

### 3.4 Phase 0 Build/Buy 게이트 (신규)

다음 4개 지표를 측정하여 Phase 0 종료 시 경영 의사결정을 받는다. 자체 구축 중단 기준을 사전에 정의해 매몰비용을 방지한다.

| 지표 | 자체 구축 유지 기준 | Buy 전환 기준 |
|---|---|---|
| 3년 TCO | 상용 대비 60% 이하 | 상용 대비 80% 초과 |
| 내부 개발 가용 공수 | 주 1.0 FTE 이상 확보 | 0.5 FTE 미만 |
| CSA 증적 작성 역량 | QA Owner 승인 가능 수준 | 외부 컨설팅 의존 필수 |
| 감사 일정 | 첫 사찰까지 9개월 이상 | 6개월 미만 |

---

## 4. 목표 아키텍처

### 4.1 전체 구조

```text
[사용자 브라우저]
        │ HTTPS
        ▼
[Keycloak] ── SSO · MFA · RBAC · 비밀번호 정책(11.300)
        │
        ▼
┌─────────────────────────────────────────────┐
│          FastAPI eQMS Core                  │
│  ├── AuditContextMiddleware (요청ID·IP·UA)  │
│  ├── Audit Service (해시체인)               │
│  ├── 문서승인 / 변경관리 / CAPA / 교육      │
│  ├── RTM / UDI / 규제모니터링 / 영향도평가  │
│  └── RAG Query Router (권한 2차 재필터)     │
└─────────────────────────────────────────────┘
        │
        ├── [PostgreSQL Primary/Standby] ── 업무 데이터 + Audit Trail
        ├── [MinIO Object Lock COMPLIANCE] ─ 원본 PDF · 서명 PDF
        ├── [Nextcloud] ─────────────────── 작성 단계 문서 협업
        ├── [DSS] ───────────────────────── PAdES 3-step 서명 · 검증
        ├── [Qdrant + Ollama] ───────────── 승인 SOP RAG (bge-m3 1024d)
        └── [Odoo] ──────────────────────── 생산·구매·재고·출하 운영기록

        모든 노드 ← NTP 동기화
```

### 4.2 기술 스택 (검증 반영)

| 영역 | 선정 | v1.0 대비 변경 | 근거 |
|---|---|---|---|
| 웹 프레임워크 | FastAPI (Python) | - | 미들웨어 기반 감사추적 용이 |
| DB | PostgreSQL 16+ (Patroni + PgBouncer) | - | 트리거 기반 감사, pgcrypto |
| 무결성 저장소 | MinIO, **Object Lock COMPLIANCE + 버전관리 (버킷 생성 시 동시 활성화)** | **모드 명시** | MinIO 공식: Object Lock은 버전관리 필수, COMPLIANCE는 root조차 변경 불가 |
| 시간 동기화 | 전 노드 NTP, MinIO는 `MINIO_NTP_SERVER` | **신규** | Part 11 §11.10(e), MinIO는 기본적으로 시스템 시계 사용 |
| 문서 협업 | Nextcloud (WebDAV) | - | 작성 단계 한정 |
| IAM | Keycloak (OIDC) | - | §11.10(d), §11.300 |
| 전자서명 | EU DSS REST, **3-step 플로우** | **플로우 전면 수정** | DSS Cookbook |
| RAG 프레임워크 | Haystack **3.x** | 2.x → 3.x | 현행 문서 버전 3.3 |
| 임베딩 | **BAAI/bge-m3 (1024차원, 8192토큰)** 또는 `dragonkue/BGE-m3-ko` | bge-small-en-v1.5(384) 폐기 | 한국어 지원 필수 |
| 벡터DB | Qdrant, **embedding_dim=1024** | 384 → 1024 | 모델 변경 연동 |
| LLM | Ollama + 한국어 지원 모델 | - | PQ-003에서 모델 선정 확정 |
| 생성 컴포넌트 | **ChatPromptBuilder → OllamaChatGenerator**, 응답은 `.text` | 타입 오류 수정 | Haystack 공식 |
| 알림 | SMTP + Slack Incoming Webhook | - | - |

### 4.3 Odoo ↔ Nextcloud 연동: FastAPI 중계형

```text
Odoo → FastAPI → Nextcloud (작성/협업)
Odoo → FastAPI → PostgreSQL Audit Trail
FastAPI → DSS → Signed PDF → MinIO (Object Lock, 최종 보존)
```

**채택 근거**: 모든 문서 행위가 감사추적에 기록되고, 권한을 단일 정책으로 관리하며, RAG 색인 대상을 승인 상태로 제한할 수 있다.

**보존 계층 분리 원칙 (신규)**: Nextcloud는 **작성·협업 단계**, MinIO Object Lock은 **승인 후 규제 기록 보존**을 담당한다. 승인 시점에 MinIO로 복사·잠금하고, 이후 Nextcloud 사본은 참조용으로만 둔다. Nextcloud 버전관리는 Part 11 §11.10(c) 보존 요건의 단독 근거로 사용하지 않는다.

---

## 5. 데이터 모델

### 5.1 도메인별 테이블 맵

| 도메인 | 주요 테이블 | Part 11 통제 |
|---|---|---|
| 사용자 | `users` | RBAC, 비활성화, 서명 유일성 |
| 문서 | `documents`, `document_versions`, `document_approvals`, `files` | 번호 유일성, 버전 불변, SHA-256 |
| 감사 | `audit_events` | append-only, 해시체인 |
| 서명 | `signatures` | 서명자·시각·의미·DTBS 결속 |
| CAPA | `nonconformances`, `capa_records`, `capa_actions`, `capa_documents` | 종결 제약 트리거 |
| 교육 | `training_courses`, `training_course_versions`, `training_assignments`, `training_completions`, `training_audit_events` | 이수기록 append-only |
| 추적성 | `requirements`, `design_items`, `test_cases`, `test_executions`, `traceability_links` | 양방향 추적 |
| 설계 | `design_projects`, `design_records`, `design_traceability` | ISO 13485 Cl.7.3 |
| 제품기준 | `medical_device_files`, `mdf_sections` | ISO 13485 Cl.4.2.3 |
| **UDI (신규)** | `device_identifiers`, `lot_records`, `supply_reports` | 820.35(c), 국내 공급내역 |
| 규제감시 | `regulatory_sources`, `regulatory_updates`, `regulatory_impact_assessments`, `csv_revalidations`, `vsr_revisions`, `notification_logs` | 변경→재검증 추적 |

### 5.2 감사추적 스키마 및 불변성

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE audit_events (
    audit_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_uuid    UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type   VARCHAR(50) NOT NULL,
    object_id     UUID NOT NULL,
    action        VARCHAR(30) NOT NULL,
    before_state  JSONB,
    after_state   JSONB,
    actor_id      UUID,
    actor_ip      INET,
    user_agent    TEXT,
    reason        TEXT,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    prev_hash     CHAR(64),
    record_hash   CHAR(64) NOT NULL
);

CREATE INDEX idx_audit_object ON audit_events(object_type, object_id, occurred_at DESC);
CREATE INDEX idx_audit_actor  ON audit_events(actor_id, occurred_at DESC);
CREATE INDEX idx_audit_action ON audit_events(action, occurred_at DESC);
```

**불변성 — 트리거 방식 확정 (D-1 반영)**

```sql
CREATE OR REPLACE FUNCTION reject_audit_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_events is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
END; $$;

CREATE TRIGGER trg_audit_no_mutation
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION reject_audit_mutation();
```

**추가 통제 (신규)**: 애플리케이션 DB 롤에서 `audit_events`에 대한 `UPDATE`·`DELETE`·`TRUNCATE` 권한을 회수하고, 테이블 소유자 계정은 운영자가 상시 사용하지 않는다. 트리거는 슈퍼유저의 `ALTER TABLE ... DISABLE TRIGGER`로 무력화될 수 있으므로, 슈퍼유저 접근을 절차적으로 통제하고 해시체인 검증을 주기 실행한다.

**해시체인 검증 쿼리**

```sql
WITH ordered_audit AS (
    SELECT audit_id, object_type, object_id, occurred_at, prev_hash, record_hash,
           LAG(record_hash) OVER (
               PARTITION BY object_type, object_id ORDER BY occurred_at, audit_id
           ) AS expected_prev_hash
    FROM audit_events
)
SELECT audit_id, object_type, object_id, occurred_at,
       CASE WHEN prev_hash IS NOT DISTINCT FROM expected_prev_hash
            THEN 'VALID' ELSE 'INVALID' END AS chain_status
FROM ordered_audit
ORDER BY object_type, object_id, occurred_at;
```

### 5.3 이중 기록 원칙

| 계층 | 기록 책임 | 구현 |
|---|---|---|
| DB 트리거 | 데이터 변경 **자체** | `fn_insert_audit_event()` + 테이블별 트리거 |
| FastAPI 미들웨어 | 사용자·IP·UA·**변경 사유**·비즈니스 맥락 | `AuditContextMiddleware` + `write_audit()` |

마스킹 대상: `password`, `token`, `secret`, `pin`, `private_key`, `keystore_password`

---

## 6. 단계별 구축 로드맵

### 6.1 전체 로드맵

| 단계 | 기간 | 목표 | 핵심 산출물 |
|---|---:|---|---|
| **Phase 0. 준비** | 2~4주 | 범위·역할·위험도 정의, **Build/Buy 게이트** | 시스템 인벤토리, GAMP 분류표, URS 초안, RACI, 3환경, TCO 비교 |
| **Phase 1. MVP** | 4주 | 감사추적·문서버전·전자서명·RAG 최소동작 | audit_events, 문서 API, DSS 3-step PoC, RAG 파일럿 |
| **Phase 2. Part 11 완성** | 6~10주 | 전 조항 대응 | 2요소 서명, 비밀번호 정책, 사본 출력, **FDA 비부인 서한 제출**, IQ/OQ 1차 |
| **Phase 3. 품질운영** | 8~12주 | NC/CAPA/교육/내부감사 | CAPA 워크플로, 교육 자동할당 |
| **Phase 4. RAG 고도화** | 6~8주 | SOP·규격 AI 비서 | 한국어 검색 품질 확보, 출처인용, 권한필터 |
| **Phase 5. 설계·제품·UDI** | 8~12주 | Design File, MDF, RTM, **UDI** | 추적성 매트릭스, MDF Index, 공급내역 보고 데이터 |
| **Phase 6. 검증·운영전환** | 3~4주 | CSA 기반 보증 완료 | VMP~VSR 전 패키지, Change Control |
| **지속운영** | 상시 | 규제 모니터링·변경통제 | 재검증, 정기검토 |

### 6.2 최소 투자 원칙

- Phase 1은 **엑셀 대체**에 집중 (등록·개정·승인·배포·회수)
- CAPA·교육은 Phase 3, 단 문서 개정 시 교육 대상자 **알림**만 Phase 1 포함
- RAG는 Phase 4, 검색 대상은 승인 문서 한정
- **보증 문서는 개발과 병행** 축적

### 6.3 Phase 0 (Sprint 0, 2주)

| ID | 작업 | 산출물 | 완료 기준 |
|---|---|---|---|
| 0-1 | 범위·역할 정의 | Scope Statement, RACI | 품질·IT·개발 책임자 승인 |
| 0-2 | URS 초안 (§8.4 기준선 사용) | URS-v0.1 | Part 11 전 조항 매핑 포함 |
| 0-3 | **CSA 위험평가** | Risk Assessment + 보증 수준 결정표 | 고위험 기능 식별, scripted/unscripted 구분 |
| 0-4 | 환경 구성 + NTP | dev/staging/prod | 환경 분리 및 시간 동기화 확인 |
| 0-5 | 저장소·CI | Git, Docker Compose, CI | 마이그레이션·테스트 자동 실행 |
| 0-6 | **Build/Buy 게이트** | TCO 비교표, 의사결정서 | 경영 승인 |
| 0-7 | **DSS 연결 스파이크** | 3-step 호출 성공 로그 | 샘플 PDF 서명·검증 1건 성공 |

> 0-7을 Phase 0에 둔 이유: DSS 3-step 플로우와 사내 CA trust anchor 등록은 아키텍처 전제이며, 여기서 막히면 전자서명 전략 자체를 재검토해야 하므로 가장 먼저 해소한다.

### 6.4 Phase 1 (4주 MVP)

| 주차 | 목표 | 완료 기준 |
|---|---|---|
| 1주차 | 감사추적 PoC | 기록 생성, UPDATE/DELETE 예외 발생 확인, 해시체인 VALID |
| 2주차 | 문서등록·버전관리 API | 문서·버전 생성, SHA-256 재계산 일치, 상태 전이 강제 |
| 3주차 | DSS PAdES 3-step | 서명·검증 Indication=TOTAL_PASSED, 변조 시 TOTAL_FAILED |
| 4주차 | RAG 파일럿 | 한글 SOP 10~20건 색인, 권한 필터 **음성 테스트 통과**, 정확도 평가 |

**1주차 일별**

| Day | 작업 | 산출물 |
|---:|---|---|
| 1 | 스키마·트리거·권한 회수 | `audit_events` |
| 2 | SQLAlchemy 모델·세션 | ORM |
| 3 | 감사추적 서비스 | `app/core/audit.py` |
| 4 | 문서 API 연결 | 생성·수정 API |
| 5 | 무결성 테스트 | UPDATE/DELETE 차단, 해시 검증 |
| 6 | 감사조회 API + **사람이 읽을 수 있는 사본 출력** | 필터 조회, PDF/CSV 내보내기 |
| 7 | PoC 보고서 | 결과·제한사항 |

**3주차 DSS PoC 절차 (수정본)**

| 단계 | 작업 | 확인 |
|---:|---|---|
| 1 | 사내 CA 인증서를 **DSS trust anchor에 등록** | 미등록 시 INDETERMINATE 발생 확인 |
| 2 | 샘플 SOP PDF 준비 | 문서번호·버전 포함 |
| 3 | `getDataToSign` 호출 (JSON, base64) | DTBS 수신, `signingDate` 기록 |
| 4 | DTBS를 서명자 키로 서명 | 서명값 획득 |
| 5 | `signDocument` 호출 (**동일 파라미터·동일 signingDate**) | 서명 PDF 수신 |
| 6 | `validateSignature` 호출 | `Indication = TOTAL_PASSED` |
| 7 | 원문 1바이트 변조 후 재검증 | `TOTAL_FAILED` |
| 8 | 감사추적 기록 | 서명자·시각·서명의미 |

### 6.5 Phase 1 스프린트 백로그

**Sprint 1: 문서등록 및 버전생성**

| ID | User Story | 수용기준 |
|---|---|---|
| 1-1 | 품질담당자는 SOP를 등록한다 | 문서번호·제목·유형·소유부서·유효일 저장 |
| 1-2 | 문서번호 자동 부여 | 중복 0, 규칙 기반 |
| 1-3 | 신규 버전 생성 | 구버전 SUPERSEDED, 신규 DRAFT |
| 1-4 | 파일 해시 생성 | SHA-256 저장, 재계산 일치 |
| 1-5 | 문서 현황 조회 | 상태 필터, 버전 이력 |

**Sprint 2: 승인요청 및 감사추적**

| ID | User Story | 수용기준 |
|---|---|---|
| 2-1 | 승인요청 생성 | 승인자·역할·기한 |
| 2-2 | 승인/반려 | 사유 필수, 상태 기록 |
| 2-3 | 전 행위 감사추적 | 생성·수정·조회·승인·반려 |
| 2-4 | 감사추적 수정·삭제 불가 | 트리거 예외 발생 |
| 2-5 | 이력 조회 + **사본 생성** | 객체·사용자·기간 필터, 인쇄/전자 사본 |

**Sprint 3: 배포 및 교육 알림**

| ID | User Story | 수용기준 |
|---|---|---|
| 3-1 | 승인 문서 배포 | 유효일 시작, 구버전 회수 |
| 3-2 | 변경 알림 발송 | 이메일/메신저 |
| 3-3 | 교육 대상자 지정 | 문서유형·역할 기반 |
| 3-4 | 배포 이력 조회 | 배포일·대상·확인 |
| 3-5 | 구버전 접근 제한 | 권한별 통제 |

**Sprint 4: 보증 준비 및 MVP 검증**

| ID | 작업 | 산출물 |
|---|---|---|
| 4-1 | URS 확정 | URS-v1.0 |
| 4-2 | CSA 위험 기반 보증 수준 확정 | Risk Control Matrix |
| 4-3 | IQ/OQ 테스트케이스 | Test Protocol |
| 4-4 | 테스트 수행 | Test Evidence |
| 4-5 | MVP 검증보고서 | MVP Validation Summary |

### 6.6 확장 우선순위

| 순위 | 모듈 | 이유 |
|---:|---|---|
| 1 | CAPA | NC→CAPA→효과성 확인이 품질시스템 핵심 (ISO 13485 Cl.8.5) |
| 2 | 교육 | 문서개정 시 할당 자동화 (Cl.6.2) |
| 3 | 설계추적성 | 820.10(c)에 따라 Class II/III 필수 |
| 4 | UDI | 820.35(c) + 국내 공급내역 보고 법정 의무 |
| 5 | 검증 패키지 | 사찰 대응 |

---

## 7. 모듈별 구현 사양

### 7.1 문서관리 · 버전관리

**상태 전이 규칙** (§11.10(f) 순서 강제 근거)

| 현재 | 허용 행위 | 다음 | 감사 action |
|---|---|---|---|
| DRAFT | 제출 | IN_REVIEW | SUBMIT |
| IN_REVIEW | 승인 서명 | APPROVED | SIGN |
| IN_REVIEW | 반려 | REJECTED | REJECT |
| APPROVED | 배포 | EFFECTIVE | DEPLOY |
| EFFECTIVE | 신규 버전 | SUPERSEDED | CREATE_VERSION |

상태 전이는 **서버 측에서만 판정**하고, 허용되지 않은 전이는 400으로 거부한 뒤 시도 자체를 감사기록에 남긴다.

**핵심 API**

| API | Method | 기능 |
|---|---|---|
| `/api/documents` | POST | 문서 등록 |
| `/api/documents/{id}/versions` | POST | 신규 버전 |
| `/api/documents/{id}/submit` | POST | 승인 요청 |
| `/api/signatures/pades/prepare` | POST | **DTBS 생성 (1단계)** |
| `/api/signatures/pades/complete` | POST | **서명 결합 (3단계)** |
| `/api/change-requests` | POST | 변경요청 |
| `/api/audit-events` | GET | 감사기록 조회 |
| `/api/audit-events/export` | GET | **사본 생성 (§11.10(b))** |
| `/api/rag/ask` | POST | SOP 질의응답 |

### 7.2 전자서명 (DSS PAdES) — 전면 수정

**구성**: `esig/dss-demonstrations` 컨테이너를 별도 REST 서비스로 기동.

**검증된 엔드포인트**

| 용도 | 경로 | 형식 |
|---|---|---|
| DTBS 생성 | `POST /services/rest/signature/one-document/getDataToSign` | JSON |
| 서명 결합 | `POST /services/rest/signature/one-document/signDocument` | JSON |
| 서명 검증 | `POST /services/rest/validation/validateSignature` | JSON |
| 서버 키 조회·서명 | `dss-server-signing-rest` (getKeys / sign) | JSON |

**3-step 플로우**

```text
[1] getDataToSign
    body: { parameters: { signingCertificate.encodedCertificate,
                          certificateChain[],
                          signatureLevel: "PAdES_BASELINE_LT",
                          signaturePackaging: "ENVELOPED",
                          digestAlgorithm: "SHA256",
                          imageParameters: {...},              ← 가시 서명란
                          blevelParams: { signingDate: <epoch ms>,
                                          commitmentTypeIndications: [...],  ← 서명 의미
                                          claimedSignerRoles: [...] } },
            toSignDocument: { bytes: <base64 PDF>, name: "SOP-QA-001_v1.0.pdf" } }
    → DTBS 반환
[2] DTBS를 서명자 개인키로 서명 → 서명값(base64)
    (서버 보관 키는 dss-server-signing-rest의 sign, 사용자 토큰은 클라이언트 측)
[3] signDocument
    body: [1]과 **완전히 동일한 parameters** + signatureValue
    → 서명된 PDF 반환
```

> **필수 주의 (I-1)**: [1]과 [3]의 `parameters`는 **`signingDate`를 포함해 완전히 동일**해야 한다. 서버에서 `signingDate`를 새로 생성하면 서명이 깨진다. → `signingDate`를 세션 상태에 저장하고 [3]에서 재사용하도록 구현하고, 단위 테스트로 고정한다.

**검증 판정 (I-2)**

```python
# 올바른 판정 로직
report = response.json()["SimpleReport"]
item = report["signatureOrTimestampOrEvidenceRecord"][0]["Signature"]
indication = item["Indication"]        # TOTAL_PASSED | INDETERMINATE | TOTAL_FAILED
sub = item.get("SubIndication")
is_valid = (indication == "TOTAL_PASSED")
# report["ValidSignaturesCount"] / report["SignaturesCount"] 도 함께 기록
```

| Indication | 처리 |
|---|---|
| `TOTAL_PASSED` | 승인 확정 |
| `TOTAL_FAILED` | 승인 거부, 편차 등록 |
| `INDETERMINATE` | 승인 보류. `SubIndication`별 조치 — `NO_CERTIFICATE_CHAIN_FOUND`는 **trust anchor 미등록**, `CRYPTO_CONSTRAINTS_FAILURE_NO_POE`는 알고리즘·타임스탬프 부재 |

**Part 11 §11.50 충족 설계 (D-4)**

| 요구 | 구현 |
|---|---|
| 서명자 인쇄명 | `imageParameters`로 PDF 가시 서명란에 렌더링 + `signatures` 테이블 기록 |
| 서명 일시 | `blevelParams.signingDate` + 서명 타임스탬프(PAdES-BASELINE-T 이상) |
| 서명 의미 | `commitmentTypeIndications`에 REVIEW/APPROVAL/RESPONSIBILITY에 대응하는 ETSI OID 기재 + 가시 서명란 텍스트 |

> **설계 결정**: 서명 레벨은 **PAdES_BASELINE_LT 이상**을 사용한다. BASELINE_B는 신뢰할 수 있는 시각 증명(POE)이 없어 인증서 만료 후 장기 검증이 불가능하며, 규제 기록 보존기간을 고려하면 부적합하다. 장기 보존이 필요한 기록은 LTA(아카이브 타임스탬프)를 검토한다.

**2요소 서명 (§11.200(a)(1))**

```text
세션 내 첫 서명  → ID + 비밀번호 전부 재입력
세션 내 후속 서명 → 비밀번호만 재입력 (ID는 세션에서 확정)
세션 종료 후 서명 → 다시 전부 재입력
```
세션 유효시간을 명시적으로 정의하고(예: 15분 무활동 시 종료), 세션 경계와 각 서명의 요소 입력 이력을 감사기록에 남긴다.

### 7.3 무결성 저장소 (MinIO) — 신규 상세

| 설정 | 값 | 근거 |
|---|---|---|
| 버킷 생성 | **Object Lock 활성화 상태로 생성** (버전관리 자동 활성화) | Object Lock은 버전관리 필수 |
| 기본 보존 모드 | **COMPLIANCE** | GOVERNANCE는 `s3:BypassGovernanceRetention` 권한자가 해제 가능. COMPLIANCE는 root 포함 전 사용자 변경 불가 |
| 보존 기간 | 규제 기록 보존정책에 따라 설정 (SOP-EQMS-005에서 확정) | §11.10(c) |
| Legal Hold | 사찰·소송 대응 시 적용 | 무기한 보호 |
| 시간 원천 | `MINIO_NTP_SERVER` 설정 | 기본값은 서버 시스템 시계 |
| IAM 정책 | **`s3:DeleteObject` 거부** | Object Lock은 버전 미지정 DELETE를 막지 못하고 Delete Marker를 생성함 (D-2) |

> **검증 포인트 (IQ-004)**: ① 버전 지정 DELETE → `400 InvalidRequest` ② 버전 미지정 DELETE → IAM 정책에서 거부되는지 확인 ③ 덮어쓰기 PUT → 새 버전 생성, 기존 버전 보존

### 7.4 CAPA 관리

**프로세스**: NC 발생 → NC 등록 → CAPA 생성 → 원인분석 → 시정/예방조치 계획 → 실행 → 효과성 확인 → 종결

**종결 제약 트리거** `fn_validate_capa_closure()`
1. 미완료 조치(`status NOT IN ('COMPLETED','VERIFIED')`) 존재 시 차단
2. `EFFECTIVENESS_CHECK` 유형 조치가 `VERIFIED` 상태로 1건 이상 없으면 차단
3. `effectiveness_check` 결과 텍스트 미기재 시 차단

**분류값**: 원인분석 5WHY/FISHBONE/FMEA/FTA/OTHER · NC 소스 INTERNAL_AUDIT/CUSTOMER_COMPLAINT/PRODUCTION/SUPPLIER/REGULATORY/OTHER · 심각도 LOW/MEDIUM/HIGH/CRITICAL

**820.35(a) 연계 (신규)**: NC 소스가 `CUSTOMER_COMPLAINT`인 경우 **불만 기록 7개 필수항목**(기기명, 접수일, UDI/UPC 등 식별자, 불만자 성명·주소·전화, 불만 내용, 시정조치, 회신)을 필수 입력으로 강제한다. 조사를 생략하는 경우 **생략 사유 기록**을 필수화한다.

### 7.5 교육·이수관리

**프로세스**: 문서 승인 → 교육과정 버전 연결 → 대상 역할 자동 할당 → 이수 → 평가·인증서 → 감사추적

**원칙**: 과정/버전/할당/이수 분리 · 승인 시 `target_roles` 기준 자동 할당(기본 기한 +14일) · 이수기록 append-only · 재교육은 신규 이수기록

**트리거**: `trg_assign_training_on_approval` (`document_versions` AFTER UPDATE, `status='APPROVED'`)

### 7.6 설계추적성 (RTM)

**체인**: Regulatory Requirement → User Need → System Requirement → Design Specification → Implementation → Test Case → Test Execution → Validation Evidence

**관계 유형**: `TRACES_TO` / `IMPLEMENTED_BY` / `VERIFIED_BY` / `VALIDATED_BY` / `MITIGATED_BY` / `DERIVES_FROM`

**필수 운영 쿼리**: ① RTM 전체 조회 ② **미커버 요구사항 리포트**(`VERIFIED_BY` 링크 0건, 우선순위 역순)

**RTM 기준선 (규제 참조 수정본)**

| URS ID | 위험 ID | 설계 ID | 시험 ID | 규제 참조 |
|---|---|---|---|---|
| URS-DC-001 | R-003 | DS-DOC-001 | OQ-DOC-001 | ISO 13485 Cl.4.2.4 |
| URS-AT-001 | R-001 | DS-AT-001 | OQ-AT-001 | 21 CFR 11.10(e) |
| URS-AT-002 | R-001 | DS-AT-002 | OQ-AT-002 | 21 CFR 11.10(e) |
| URS-AT-004 | R-008 | DS-AT-004 | OQ-AT-004 | 21 CFR 11.10(b) |
| URS-SIG-001 | R-002 | DS-SIG-001 | OQ-SIG-001 | 21 CFR 11.70 |
| URS-SIG-003 | R-002 | DS-SIG-003 | OQ-SIG-003/004 | 21 CFR 11.50 |
| URS-SIG-005 | R-009 | DS-SIG-005 | OQ-SIG-005 | 21 CFR 11.200(a)(1) |
| URS-CAPA-003 | R-006 | DS-CAPA-003 | OQ-CAPA-003 | ISO 13485 Cl.8.5.2 |
| URS-TRN-003 | R-007 | DS-TRN-003 | OQ-TRN-003 | ISO 13485 Cl.6.2 |
| URS-UDI-001 | R-010 | DS-UDI-001 | OQ-UDI-001 | 21 CFR 820.35(c) |
| URS-RAG-001 | R-004 | DS-RAG-001 | OQ-RAG-001 | GAMP 5 (위험통제) |

### 7.7 설계개발 파일 · MDF

**Design and Development File (ISO 13485 Cl.7.3)**

```text
DesignProject
 ├── DesignPlan (7.3.2)        ├── DesignInputs (7.3.3)
 ├── DesignOutputs (7.3.4)     ├── DesignReviews (7.3.5)
 ├── Verification (7.3.6)      ├── Validation (7.3.7)
 ├── DesignTransfer (7.3.8)    ├── DesignChanges (7.3.9)
 ├── RiskFile (ISO 14971)      └── DesignFile (7.3.10)
```

**MDF 섹션 (Cl.4.2.3)**: `DEVICE_SPEC` / `PROCESS_SPEC` / `QA_PROCEDURE` / `PACKAGING_LABELING` / `INSTALLATION_MAINTENANCE_SERVICE`

**화면**

| 화면 | 기능 |
|---|---|
| Design Traceability Matrix | User Need → Input → Output → Risk → V&V → Change |
| MDF Index | 제품별 사양·절차·라벨링·서비스 일괄 조회 |
| Change Impact | 문서 개정 시 영향 설계·MDF·CAPA 자동 표시 |
| Audit Viewer | 기록별 생성·수정·승인·서명 이력 |

### 7.8 보안형 RAG 파이프라인 — 수정본

**색인**: `PyPDFToDocument` → `DocumentCleaner` → `DocumentSplitter(split_by="sentence")` → `SentenceTransformersDocumentEmbedder(model="BAAI/bge-m3")` → `DocumentWriter(QdrantDocumentStore(embedding_dim=1024))`

**질의**: `SentenceTransformersTextEmbedder` → `QdrantEmbeddingRetriever(top_k=5, filters=...)` → **`ChatPromptBuilder`** → **`OllamaChatGenerator`**

```python
# 응답 추출 (I-4 반영)
answer = result["generator"]["replies"][0].text   # .content 아님
```

**메타필드**: `doc_no`, `title`, `version`, `status`, `effective_date`, `owner_department`, `access_roles`

**접근제어 필터 (D-3 반영: 이중 방어)**

```python
# 1차: 저장소 레벨 필터
filters = {
    "operator": "AND",
    "conditions": [
        {"field": "meta.status", "operator": "==", "value": "APPROVED"},
        {"field": "meta.access_roles", "operator": "in", "value": current_user.roles},
    ],
}

# 2차: 애플리케이션 레벨 재필터 (필수)
docs = [d for d in retrieved
        if d.meta.get("status") == "APPROVED"
        and set(d.meta.get("access_roles", [])) & set(current_user.roles)]
```

> 배열 payload에 대한 `in` 연산자 동작은 Document Store 구현에 의존한다고 Haystack 공식 문서가 명시한다. 따라서 **저장소 필터만 신뢰하지 않고** 애플리케이션에서 재필터링하며, OQ-RAG-003에서 **권한 없는 역할로 비공개 문서가 검색되지 않는 음성 테스트**를 반드시 수행한다.

**응답 정책**
1. 제공된 내부 문서 근거만 사용
2. 근거 없으면 "확인된 내부 문서 근거가 없습니다"
3. 문서번호·제목·버전·유효일 반드시 인용
4. 최종 판단·승인은 품질담당자 수행임을 명시
5. 질의·검색 문서·응답 요약을 감사추적에 기록
6. 비밀번호·토큰·PIN 로그 마스킹

**평가 기준**

| 항목 | 측정 | 통과 기준 |
|---|---|---|
| 정확성 | 전문가 3점 척도 | 80% 이상 |
| 출처일치 | 출처 대조 | 100% |
| 완결성 | 누락 항목 수 | — |
| 환각률 | 근거없는 문장/전체 | 10% 미만 |
| 검색 재현율 | Hit@5 | PQ-003에서 기준 확정 |
| **권한 격리** | 음성 테스트 통과율 | **100% (0건 유출)** |

### 7.9 UDI 및 공급내역 (신규 — v1.0 미결 해소)

**규제 근거 2단**

| 구분 | 요구 | 출처 |
|---|---|---|
| 미국 | UDI 부여 체계를 **21 CFR Part 830**에 따라 문서화 | 21 CFR 820.10(b)(1) |
| 미국 | **각 기기 또는 배치별로 UDI 기록** | 21 CFR 820.35(c) |
| 미국 | 불만·서비스 기록에 UDI/UPC 기재 | 21 CFR 820.35(a)(3), (b)(2) |
| 국내 | **매월 말일까지 전월 공급내역(공급기관·수량·공급가격)을 의료기기통합정보시스템에 제출** | 의료기기법 시행규칙 |
| 국내 | 허가·신고된 기기는 **출고 시 최초 1회만 UDI-DI 등록** | 식약처 민원상담 사례집(2026-08-19 개정) |

**시스템 범위 결정**

| 기능 | 범위 | 비고 |
|---|---|---|
| UDI-DI 마스터 관리 | **포함** | 모델별 1회 등록, 변경 이력 추적 |
| Lot/Serial 기록 | **포함** | 제조·출하 단위 UDI 기록 |
| 불만·서비스 기록 UDI 연계 | **포함** | CAPA 모듈과 결합 |
| 월별 공급내역 보고 **파일 생성** | **포함** | 전월 공급기관·수량·공급가격 집계, 검증 후 산출 |
| 통합정보시스템 **자동 전송** | **제외** | 공개된 기관 간 연계 규격을 확인하지 못함 |

> **판단 근거 및 후속 조치**: 공개 자료상 보고는 의료기기통합정보시스템(UDI 추적관리시스템)을 통한 제출로 규정되어 있으나, **외부 시스템이 직접 호출할 수 있는 공식 API 규격은 확인되지 않았다.** 따라서 v2.0에서는 **보고 파일 생성까지를 범위로 확정**하고 제출은 담당자가 포털에서 수행한다. 자동 전송이 필요하면 **의료기기통합정보센터 콜센터(1899-9351)** 또는 한국의료기기안전정보원에 연계 규격 제공 여부를 질의하여 Phase 5 착수 전 확정한다. 이 질의는 Phase 0 체크리스트 항목으로 등록한다.

**보고 전 자체 검증 (신규)**: 제출 전 ① 전월 출하 Lot 수와 보고 건수 일치 ② UDI-DI 미등록 모델 0건 ③ 공급기관 코드 유효성 — 3개 항목을 시스템이 자동 점검하고 결과를 감사기록에 남긴다.

### 7.10 규제 변경 모니터링

**흐름**: 규제 소스 → 해시 비교 + 키워드 필터 → 변경 로그 → 자동 영향도 평가 → 변경관리/재검증 → VSR 갱신 → 알림

**모니터링 대상 (수정본)**

| 대상 | 소스 | 주기 |
|---|---|---|
| FDA Guidance | FDA Guidance Documents 검색 페이지 | 주 1회 |
| 21 CFR Part 11 | eCFR Title 21 Part 11 | 주 1회 |
| **21 CFR Part 820 (QMSR)** | eCFR Title 21 Part 820 | 주 1회 |
| **21 CFR Part 830 (UDI)** | eCFR Title 21 Part 830 | 월 1회 |
| **FDA CSA 가이던스** | FDA 가이던스 페이지 | 월 1회 |
| GAMP 5 | ISPE 공지 | 월 1회 |
| EU Annex 11 | EudraLex Vol.4 | 월 1회 |
| ISO 13485 | ISO 공지 | 분기 1회 |
| **식약처 의료기기 공지·사례집** | MFDS | 월 1회 |

**감지 방식**: 페이지 SHA-256 비교 **AND** 키워드 매칭 시에만 알림. 페이지 전체 해시는 배너·광고 변경에도 반응하므로, **본문 영역만 추출한 뒤 해시**하도록 구현하여 오탐을 줄인다.

**자동 영향도 평가 규칙 (수정본)**

| 키워드 | 영향 대상 | 판정 | 재검증 범위 |
|---|---|---|---|
| `electronic signatures` | URS-SIG, RTM, DSS | MAJOR | TARGETED |
| `audit trail` | URS-AT, DB, RTM | MAJOR | TARGETED |
| `data integrity` | URS-AT, 백업, 감사추적 | MAJOR | TARGETED |
| `computer software assurance` | VMP, Risk, RTM | MINOR | TARGETED |
| `design and development` | 설계파일, RTM | MAJOR | TARGETED |
| `medical device file` | URS-DC, MDF | MINOR | TARGETED |
| **`unique device identification`** | **UDI 모듈, 820.35** | **MAJOR** | **TARGETED** |
| `control of records` | 전 기록 모듈 | MAJOR | TARGETED |
| `training` | 교육모듈, SOP | MINOR | NONE |
| `quality management system regulation` | 전체 QMS | MAJOR | FULL |

**합산 규칙**: 결론 MAJOR > MINOR > NO_IMPACT, 범위 FULL > TARGETED > NONE. `csv_revalidation_required = (scope != 'NONE')`

> **운영 원칙 (신규)**: 자동 평가 결과는 **초안**이며, `approval_status`가 `APPROVED`가 되기 전에는 재검증을 개시하지 않는다. 키워드 기반 판정은 오탐·미탐이 있으므로 **QA 담당자 검토를 거쳐야 규제 영향 평가로 성립**한다. 이 점을 SOP-EQMS-006에 명시한다.

---

## 8. 검증 전략 — CSA 기반 (전면 개정)

### 8.1 전략 전환 근거

FDA CSA 최종 가이던스(2025-09-24, 2026-02-03 개정)는 GPSV Section 6을 대체하며, 생산·품질시스템 소프트웨어에 **위험 기반 보증**을 적용하도록 한다. 핵심은 저위험 기능의 과잉 시험·과잉 문서화를 줄이고 **고위험 영역에 자원을 집중**하되, 그 판단 근거를 감사 가능하게 남기는 것이다. 본 프로젝트는 소규모 조직의 제한된 공수를 고려해 이 접근을 채택한다.

### 8.2 보증 수준 결정 프로세스

```text
[1] 이 소프트웨어 기능이 생산 또는 품질시스템의 일부인가?
      아니오 → 보증 활동 불필요 (근거만 기록)
      예 ↓
[2] 고장 시 제품 품질·환자 안전에 직접 영향을 주는가? (direct impact)
      예 → 고위험
      아니오 ↓
[3] 고장이 다른 통제·검토로 탐지되는가?
      탐지됨 → 저위험 / 탐지 안 됨 → 중위험
```

| 위험 수준 | 대상 기능 예시 | GAMP 분류 | 보증 활동 | 증적 |
|---|---|---|---|---|
| **고위험** | 감사추적 불변성, 전자서명·검증, 승인 상태 전이, CAPA 종결 제약, UDI 기록 | Cat.5 | **Scripted testing** (사전 작성 프로토콜, 단계별 기대결과) | 프로토콜, 실행기록, 스크린샷, DB 증적, 서명 |
| **중위험** | 버전관리, 교육 할당, RTM 조회, 공급내역 집계 | Cat.4~5 | **Unscripted — 시나리오 기반** | 시나리오 요약, 결과, 이슈 로그 |
| **저위험** | 목록 필터, 화면 정렬, 대시보드 표시 | Cat.4 | **Unscripted — Ad-hoc / 탐색적** | 수행 사실 및 결론 기록 |

> **중요**: 위험 수준이 낮다고 시험을 생략하는 것이 아니라 **시험의 형식과 문서화 깊이를 조정**하는 것이다. 모든 기능은 최소 1회 이상 의도된 용도에 대해 수행·확인되어야 한다.

### 8.3 검증 패키지 구성

| 문서 | 목적 | 작성 시점 |
|---|---|---|
| VMP | 보증 전략·범위·역할 | 프로젝트 시작 |
| URS | 사용자·규제 요구사항 | 요구사항 확정 |
| **Risk & Assurance Plan** | 기능별 위험·보증 수준 결정 근거 | URS 이후 |
| RTM | URS-위험-설계-시험 연결 | 테스트 설계 |
| IQ Protocol | 설치·환경·구성 | 설치 전 |
| OQ Protocol | 기능·경계·오류조건 (고위험 scripted) | 개발 완료 후 |
| PQ Protocol | 실제 업무 시나리오 | 운영 전 |
| Test Evidence | 결과·스크린샷·로그 | 테스트 실행 |
| Deviation Log | 편차·원인·조치·재시험 | 편차 발생 |
| VSR | 요약·잔여리스크·운영승인 | 검증 완료 |
| SOP | 운영·백업·장애·변경 | 운영 전 |
| Training Record | 교육·이수 증적 | 운영 전 |

### 8.4 URS 요구사항 기준선 (규제 참조 수정본)

분류: **FR**(Functional) / **NFR**(Non-Functional) / **CR**(Compliance) / **SR**(Security)

| ID | 분류 | 요구사항 | 수용기준 | 위험 | 규제 참조 | 검증 |
|---|---|---|---|---|---|---|
| URS-DC-001 | FR | SOP를 등록할 수 있다 | 문서번호·제목·유형·소유자 저장 | 중 | ISO 13485 Cl.4.2.4 | OQ |
| URS-DC-002 | FR | 신규 버전을 생성할 수 있다 | 구버전 SUPERSEDED | 고 | Cl.4.2.4 | OQ |
| URS-DC-003 | FR | 문서는 승인 후 배포된다 | 승인 전 배포 불가 | 고 | Cl.4.2.4 / 11.10(f) | OQ |
| URS-DC-004 | CR | 시스템 문서도 변경통제 대상이다 | 변경 이력 감사추적 | 중 | 11.10(k)(2) | OQ |
| URS-AT-001 | CR | 생성·수정·승인 행위는 감사추적된다 | 감사기록 생성 | 고 | 11.10(e) | OQ |
| URS-AT-002 | CR | 감사기록은 수정·삭제될 수 없다 | UPDATE/DELETE 예외 발생 | 고 | 11.10(e) | OQ |
| URS-AT-003 | CR | 감사기록은 사용자·시각·사유를 포함한다 | 필수 필드 존재 | 고 | 11.10(e) | OQ |
| URS-AT-004 | CR | 감사기록의 인쇄 사본과 전자 사본을 생성한다 | PDF + CSV/JSON 출력 | 중 | 11.10(b) | OQ |
| URS-AT-005 | NFR | 감사기록은 대상 기록과 동일 기간 보존된다 | 보존정책 적용 확인 | 고 | 11.10(e) | IQ/PQ |
| URS-SIG-001 | CR | 승인자는 PAdES 전자서명을 수행한다 | Indication=TOTAL_PASSED | 고 | 11.70 | OQ |
| URS-SIG-002 | CR | 서명 후 원문 변경은 탐지된다 | 변조 시 TOTAL_FAILED | 고 | 11.70 | OQ |
| URS-SIG-003 | CR | 서명자명·시각·서명의미를 기록한다 | 메타데이터 저장 | 고 | 11.50(a) | OQ |
| URS-SIG-004 | CR | 서명 정보가 사람이 읽을 수 있는 형태에 포함된다 | PDF 가시 서명란 표시 | 고 | 11.50(b) | OQ |
| URS-SIG-005 | CR | 서명은 2개 식별요소로 수행된다 | 세션 규칙 §7.2 준수 | 고 | 11.200(a)(1) | OQ |
| URS-SEC-001 | SR | 권한자만 접근한다 | 역할 외 403 | 고 | 11.10(d) | OQ |
| URS-SEC-002 | SR | 권한 확인을 수행한다 | 서명·변경 권한 검사 | 고 | 11.10(g) | OQ |
| URS-SEC-003 | SR | ID/비밀번호 통제를 적용한다 | 유일성·주기변경·회수·무단사용 탐지 | 고 | 11.300 | OQ |
| URS-CAPA-001 | FR | NC를 등록할 수 있다 | NC번호·심각도·소유자 | 중 | Cl.8.5.2 | OQ |
| URS-CAPA-002 | FR | NC에서 CAPA를 생성할 수 있다 | NC-CAPA 연결 | 중 | Cl.8.5.2 | OQ |
| URS-CAPA-003 | CR | CAPA 종결 시 효과성 확인이 필요하다 | 미완료 시 차단 | 고 | Cl.8.5.2 | OQ |
| URS-CAPA-004 | CR | 불만 기록은 필수항목을 포함한다 | 7개 항목 필수 입력 | 고 | 820.35(a) | OQ |
| URS-TRN-001 | FR | 문서 승인 시 교육을 할당한다 | 대상자별 기록 생성 | 중 | Cl.6.2 | OQ |
| URS-TRN-002 | FR | 이수 여부를 관리한다 | 이수일·평가·상태 | 중 | Cl.6.2 | OQ |
| URS-TRN-003 | CR | 교육기록은 변경·삭제될 수 없다 | append-only | 고 | Cl.6.2 / 11.10(e) | OQ |
| URS-RTM-001 | FR | 요구사항을 설계·시험과 연결한다 | 관계 저장 | 중 | Cl.7.3.10 | OQ |
| URS-RTM-002 | FR | 커버리지를 확인한다 | 미커버 리포트 | 중 | Cl.7.3.10 | OQ |
| URS-UDI-001 | CR | 기기·배치별 UDI를 기록한다 | Lot별 UDI 저장 | 고 | 820.35(c) | OQ |
| URS-UDI-002 | FR | 월별 공급내역 보고 파일을 생성한다 | 공급기관·수량·가격 집계 | 중 | 의료기기법 시행규칙 | OQ |
| URS-RAG-001 | FR | 승인 SOP를 검색할 수 있다 | 승인 문서만 검색 | 고 | GAMP 5 | OQ |
| URS-RAG-002 | FR | 근거 없으면 근거 없음을 응답한다 | 환각 방지 | 중 | GAMP 5 | OQ |
| URS-RAG-003 | CR | 질의와 출처는 감사추적된다 | 질의·문서·응답 기록 | 중 | 11.10(e) | OQ |
| URS-INF-001 | NFR | 서버·OS는 승인 사양과 일치한다 | 사양 일치 | 중 | GAMP 5 | IQ |
| URS-INF-002 | NFR | PostgreSQL 16 이상을 사용한다 | 버전 확인 | 중 | GAMP 5 | IQ |
| URS-STG-001 | SR | 원본 덮어쓰기·삭제를 방지한다 | Object Lock + IAM 거부 | 고 | 11.10(c) | IQ |
| URS-AT-006 | NFR | 서버 시간은 동기화된다 | NTP 오차 허용범위 | 고 | 11.10(e) | IQ |

### 8.5 위험평가 기준선

| Risk ID | 기능 | 위험 | 영향 | 심각도 | 발생 | 등급 | 통제 | 검증 |
|---|---|---|---|---:|---:|---|---|---|
| R-001 | 감사추적 | 기록 삭제 | 규제 기록 손실 | 5 | 2 | 고 | 트리거 예외 + 권한 회수 | OQ-AT-002 |
| R-002 | 전자서명 | 무단 서명 | 무효 승인 | 5 | 2 | 고 | RBAC + 2요소 + 인증서 | OQ-SIG-001/005 |
| R-003 | 문서버전 | 구버전 덮어쓰기 | 이력 상실 | 4 | 3 | 고 | 버전 불변 + Object Lock | OQ-DOC-002 |
| R-004 | RAG | 비승인·비권한 문서 검색 | 잘못된 품질 판단·정보 유출 | 4 | 3 | 고 | 필터 이중화 | OQ-RAG-001/003 |
| R-005 | RAG | 근거 없는 답변 | 오해 유발 | 4 | 3 | 고 | 근거없음 정책 + 출처 강제 | OQ-RAG-002 |
| R-006 | CAPA | 효과성 미확인 종결 | 재발 | 4 | 3 | 고 | 종결 제약 트리거 | OQ-CAPA-003 |
| R-007 | 교육 | 이수기록 변조 | 증적 상실 | 4 | 2 | 고 | append-only 트리거 | OQ-TRN-003 |
| R-008 | 감사추적 | 사본 제공 불가 | 사찰 대응 실패 | 4 | 2 | 고 | 출력 API | OQ-AT-004 |
| R-009 | 전자서명 | 단일요소 서명 | Part 11 위반 | 5 | 2 | 고 | 세션 기반 2요소 | OQ-SIG-005 |
| R-010 | UDI | UDI 미기록·오기록 | 추적 불가, 법정 위반 | 5 | 2 | 고 | 필수 입력 + 출하 전 검증 | OQ-UDI-001 |
| R-011 | 저장소 | 버전 미지정 DELETE로 객체 은폐 | 기록 접근 불가 | 4 | 3 | 고 | IAM `s3:DeleteObject` 거부 | IQ-004 |
| R-012 | 시간 | 시계 불일치로 시각 신뢰성 상실 | 감사추적 무효 | 4 | 2 | 고 | NTP + MINIO_NTP_SERVER | IQ-006 |

### 8.6 IQ 프로토콜

| ID | 시험 항목 | URS | 방법 | 기대결과 |
|---|---|---|---|---|
| IQ-001 | 서버·OS 확인 | URS-INF-001 | 사양·버전 확인 | 승인 사양 일치 |
| IQ-002 | PostgreSQL 확인 | URS-INF-002 | `SELECT version();` | 16 이상 |
| IQ-003 | 감사추적 객체 확인 | URS-AT-001 | 테이블·인덱스·트리거·권한 확인 | 전 객체 존재, 앱 롤 UPDATE/DELETE 권한 없음 |
| IQ-004 | **MinIO Object Lock 확인** | URS-STG-001 | ① 버전관리 활성 ② COMPLIANCE 기본보존 ③ 버전지정 DELETE ④ 버전미지정 DELETE | ①② 활성 ③ 400 InvalidRequest ④ IAM 거부 |
| IQ-005 | DSS 서비스 및 trust anchor | URS-SIG-001 | 헬스체크 + 사내 CA 등록 확인 | HTTP 200, CA 신뢰목록 등재 |
| IQ-006 | **시간동기화** | URS-AT-006 | NTP 상태 + `MINIO_NTP_SERVER` | 허용 오차 내, 변수 설정됨 |
| IQ-007 | 환경 분리 | VMP | dev/staging/prod 접근 경로·계정 분리 확인 | 교차 접근 불가 |
| IQ-008 | 백업 구성 | URS-AT-005 | 백업 스케줄·보존정책 확인 | 정책대로 설정 |

### 8.7 OQ 프로토콜 (고위험 = scripted)

| ID | 시험 항목 | URS | 기대결과 |
|---|---|---|---|
| OQ-DOC-001 | 문서 등록 | URS-DC-001 | 문서 생성 + 감사기록 1건 |
| OQ-DOC-002 | 신규 버전 생성 | URS-DC-002 | 구버전 SUPERSEDED, 신규 DRAFT |
| OQ-DOC-003 | **상태 전이 강제** | URS-DC-003 | 허용되지 않은 전이 400 거부 + 시도 기록 |
| OQ-DOC-004 | 시스템 문서 변경통제 | URS-DC-004 | 변경 이력 감사추적 |
| OQ-AT-001 | 감사추적 생성 | URS-AT-001 | CREATE·UPDATE 기록 존재 |
| OQ-AT-002 | 감사추적 변경 차단 | URS-AT-002 | UPDATE·DELETE 모두 **예외 발생** |
| OQ-AT-003 | 해시체인 무결성 | URS-AT-003 | 전 레코드 VALID |
| OQ-AT-004 | **사본 생성** | URS-AT-004 | PDF 및 CSV/JSON 출력, 내용 일치 |
| OQ-SIG-001 | PAdES 3-step 서명 | URS-SIG-001 | Indication = TOTAL_PASSED |
| OQ-SIG-002 | 변조 탐지 | URS-SIG-002 | TOTAL_FAILED |
| OQ-SIG-003 | 서명 메타데이터 | URS-SIG-003 | 서명자·시각·의미 DB 기록 |
| OQ-SIG-004 | **가시 서명란** | URS-SIG-004 | PDF 출력물에 3항목 표시 |
| OQ-SIG-005 | **2요소 서명 세션 규칙** | URS-SIG-005 | 첫 서명 전요소, 후속 1요소, 세션 종료 후 전요소 |
| OQ-SEC-001 | 접근 통제 | URS-SEC-001 | 역할 외 403 |
| OQ-SEC-002 | 권한 확인 | URS-SEC-002 | 비권한자 서명 차단 |
| OQ-SEC-003 | 입력 검증 | URS-SEC-003 | 서버 측 거부 |
| OQ-SEC-004 | 비밀번호 통제 | URS-SEC-003 | 중복 불가, 만료 강제, 실패 시 알림 |
| OQ-CAPA-003 | CAPA 종결 제약 | URS-CAPA-003 | 미완료·효과성 누락 시 차단 |
| OQ-CAPA-004 | 불만 필수항목 | URS-CAPA-004 | 미입력 시 저장 거부 |
| OQ-TRN-003 | 교육기록 불변성 | URS-TRN-003 | 변경·삭제 차단 |
| OQ-UDI-001 | **UDI 기록** | URS-UDI-001 | Lot별 UDI 저장, 미입력 시 출하 차단 |
| OQ-RAG-001 | 승인 문서만 검색 | URS-RAG-001 | DRAFT 미검색 |
| OQ-RAG-002 | 근거 없는 질문 | URS-RAG-002 | "근거 없음" 응답 |
| OQ-RAG-003 | **권한 격리 음성 테스트** | URS-RAG-001 | 비권한 역할 계정으로 **0건 유출** |

### 8.8 PQ 시나리오

| ID | 시나리오 | 수용기준 |
|---|---|---|
| PQ-001 | SOP 개정 전 과정: v1.0 등록 → 검토 → PAdES 서명 → 배포 → RAG 검색 → v2.0 생성 → v1.0 SUPERSEDED | 전 상태 전이·서명 기록, 감사추적 완전성, 승인 문서만 검색 |
| PQ-002 | CAPA 문서 연계: Odoo CAPA → 문서 등록 → 저장 → 승인·서명 → 감사추적 | CAPA-문서 연결, 원본·서명본 구분, 기록 완전성 |
| PQ-003 | RAG 사용성 평가 (품질담당자 3~5명, 문서당 5~10문항, **한글 질의**) | 정확성 80%↑, 환각률 10%↓, 출처 100%, 권한 유출 0 |
| PQ-004 | 백업·복구: DB·원본 백업 → 장애 → 복구 | DB·원본 복구 성공, 감사추적 연속성, 해시체인 VALID |
| PQ-005 | **월별 공급내역 보고** (신규): 출하 데이터 → 집계 → 자체 검증 → 보고 파일 생성 | 전월 Lot 수 일치, UDI 미등록 0건, 파일 서식 적합 |
| PQ-006 | **사찰 대응 리허설** (신규): 임의 기록 1건 지목 → 생성~승인~서명 전 이력 제시 + 인쇄/전자 사본 제출 | 30분 내 제시, 사본 내용 일치 |

### 8.9 릴리스 기준

- 고위험 테스트 **100% 통과**
- 모든 URS에 대응 시험 존재 (미커버 0건)
- 편차 없음 또는 **승인된 편차만** 존재
- 해시체인 검증 통과
- 변조 탐지 통과
- RAG 권한 유출 0건
- **FDA 비부인 서한 제출 완료** (해당 시)
- 교육기록·SOP·백업복구 증적 완비

### 8.10 VSR 필수 구성

시스템·범위, 프로토콜·수용기준, **보증 수준 결정 근거(CSA)**, 결과, 편차, 미해결 항목, 추적성 확인, 릴리스 판정, 승인자 서명. 판정은 `Validated` / `Validated with restrictions` / `Not validated`.

---

## 9. 운영 거버넌스

### 9.1 운영 SOP

| SOP | 내용 |
|---|---|
| SOP-EQMS-001 | 문서 등록·개정·승인·배포 절차 |
| SOP-EQMS-002 | 감사추적 조회·검증·사본 제공 절차 |
| SOP-EQMS-003 | **전자서명 발급·사용·폐기 및 서명 책임 정책** (§11.10(j)) |
| SOP-EQMS-004 | RAG 검색·출처확인·환각 대응 절차 |
| SOP-EQMS-005 | 백업·복구·장애 대응 및 **기록 보존기간** 절차 |
| SOP-EQMS-006 | 변경관리·규제 영향평가·재검증 절차 |
| SOP-EQMS-007 | **UDI 부여·기록 및 공급내역 보고 절차** (신규) |
| SOP-EQMS-008 | **계정·비밀번호 관리 절차** (§11.300) (신규) |

### 9.2 변경통제

- dev → staging → prod 이관 시 **이관계획·테스트결과·승인기록** 보관
- 변경 발생 시 영향평가 → 재검증 범위 판정 → VSR 개정
- **연 1회 정기검토(Periodic Review)**: 해시체인 전수 검증, 권한 재인증, 백업 복구 테스트, 규제 변경 반영 현황 점검
- 시스템 문서 자체도 문서통제 대상 (§11.10(k))

### 9.3 저장소 구조

```text
medical-eqms/
├── backend/
│   ├── app/
│   │   ├── core/      (config, database, security, audit, middleware)
│   │   ├── models/ schemas/ routers/ services/
│   │   └── main.py
│   ├── alembic/  tests/  pyproject.toml
├── rag/
│   ├── indexing_pipeline.py  query_pipeline.py  evaluation/
├── regulatory/
│   ├── sources.py  monitor.py  scheduler.py
├── udi/
│   ├── supply_report.py  validators.py
├── dss/
│   ├── docker-compose.dss.yml  trust_anchors/  postman/
├── docs/
│   ├── VMP.md  URS.md  Risk_Assurance_Plan.md  RTM.md
│   ├── IQ_OQ_PQ.md  Validation_Report.md
├── docker-compose.yml
└── README.md
```

### 9.4 컨테이너 구성

| 서비스 | 이미지 | 포트 | 비고 |
|---|---|---|---|
| api | ./backend | 8000 | |
| db | postgres:16 | 5432 | Primary/Standby |
| minio | minio/minio | 9000/9001 | Object Lock 버킷, `MINIO_NTP_SERVER` |
| qdrant | qdrant/qdrant | 6333 | embedding_dim 1024 |
| ollama | ollama/ollama | 11434 | 한국어 모델 |
| dss | esig/dss-demonstrations | 8080 | trust anchor 마운트 |

---

## 10. 리스크 및 완화

| 리스크 | 내용 | 완화책 |
|---|---|---|
| 오픈소스 감사 수용성 | 검사관 수용 여부 | CSA 기반 보증 증적으로 "의도된 용도 적합성" 입증 (출처 무관) |
| Part 11 불변성 | 슈퍼유저의 트리거 무력화 | 권한 회수 + 슈퍼유저 절차 통제 + 해시체인 주기 검증 |
| **DSS 3-step 복잡도** | signingDate 불일치로 서명 실패 | Phase 0 스파이크 + 단위 테스트 고정 + 세션 상태 관리 |
| **DSS trust anchor** | 사내 CA 미등록 시 INDETERMINATE | IQ-005에서 등재 확인, 인증서 갱신 시 재등록 절차화 |
| LLM 환각 | SOP 답변 오류 | 출처 인용 강제, 근거없음 허용, 인간 검토 |
| **한국어 검색 품질** | 임베딩·청킹 부적합 | bge-m3 채택 + PQ-003에서 Hit@5 기준 확정 후 모델 고정 |
| **RAG 권한 유출** | 배열 필터 동작 저장소 의존 | 이중 필터 + OQ 음성 테스트 100% |
| 검증 비용 | 문서 과다 | CSA 위험 기반 차등 적용 |
| **UDI 보고 누락** | 월별 법정 보고 미이행 | 보고 전 자동 자체검증 + 월말 알림 스케줄 |
| 운영 중단 | DB·스토리지 장애 | 이중화 + PQ-004 복구 검증 |
| 규제 변경 추적 실패 | 오탐으로 알림 신뢰도 하락 | 본문 영역 한정 해시 + QA 검토 게이트 |

---

## 11. 완료 기준 (DoD)

| 영역 | 완료 기준 |
|---|---|
| 문서관리 | 번호 중복 0, 전 버전 보존, 상태 전이 강제 |
| 감사추적 | DB 트리거 + 앱 이중 기록, UPDATE/DELETE 예외, 해시체인 VALID, **인쇄·전자 사본 생성** |
| 무결성 | SHA-256 100% 일치, Object Lock COMPLIANCE, **버전 미지정 DELETE 차단** |
| 전자서명 | 3-step 성공, Indication TOTAL_PASSED, 변조 시 FAILED, **가시 서명란 3항목**, **2요소 세션 규칙** |
| 접근통제 | 역할 외 403, 비밀번호 정책 적용, 무단사용 탐지 |
| CAPA | NC-CAPA-조치-효과성 추적, 불만 7항목 필수 |
| 교육 | 승인 시 자동 할당, 이수기록 append-only |
| RTM | 양방향 연결, 미커버 0건 |
| UDI | Lot별 UDI 기록, 월별 보고 파일 생성 및 자체검증 통과 |
| RAG | 승인 문서만 검색, 출처 100%, **권한 유출 0건**, 한국어 정확성 80%↑ |
| 시간 | 전 노드 NTP 동기화, MinIO NTP 설정 |
| 백업 | 복구 테스트 통과, 감사추적 연속성 |
| 규제 모니터링 | 변경 감지·알림·QA 검토 게이트 동작 |
| 검증 | VMP-URS-Risk&Assurance-RTM-IQ/OQ/PQ-VSR 연결 완료 |

---

## 12. 다음 4주 실행계획

| 주차 | 목표 | 산출물 | 담당 |
|---|---|---|---|
| **1주차** | 감사추적 PoC + 사본 출력 | 스키마·트리거·권한 회수, 미들웨어, 무결성 테스트, PDF/CSV 출력 | 개발 + IT Validation |
| **2주차** | 문서등록·버전관리 + 상태 전이 | 문서·버전·해시 API, 전이 강제 로직 | 개발 |
| **3주차** | **DSS 3-step 서명** | trust anchor 등록, getDataToSign/signDocument/validateSignature, 변조 탐지 | 개발 + QA |
| **4주차** | RAG 파일럿 (한국어) | bge-m3 색인 10건, 권한 음성 테스트, 평가 질문 세트 | 개발 + 품질담당자 |

**병행 (상시)**: URS v1.0 확정 및 QA Owner 승인 / CSA Risk & Assurance Plan 작성 / IQ·OQ 테스트케이스 축적

**즉시 착수 (Day 1)**

1. Phase 0 Scope·RACI 확정 회의
2. dev/staging/prod 3환경 분리 + **전 노드 NTP 동기화**
3. `docker-compose.yml` 기준 로컬 스택 기동 (db, minio **Object Lock 버킷 생성**, qdrant, ollama, dss)
4. **DSS 스파이크**: 사내 CA 등록 후 샘플 PDF 3-step 서명·검증 1건 성공시키기 (가장 큰 미지 요소)
5. URS의 규제 참조 컬럼을 **현행 조문 체계로 전면 재작성** (구 820.30/.100/.180 인용 전량 제거)
6. GAMP 분류 + CSA 위험 수준 결정표 작성
7. **의료기기통합정보센터(1899-9351)에 공급내역 연계 규격 제공 여부 질의**
8. Build/Buy TCO 비교 착수

---

## 13. 핵심 설계 결정 요약

| # | 결정 | 근거 |
|---|---|---|
| 1 | Odoo·Nextcloud는 운영 기반, Part 11 통제는 FastAPI 커스텀 계층 | 상용/오픈소스 제품이 Part 11을 보장하지 않음 |
| 2 | 감사추적 불변성은 RULE이 아닌 **TRIGGER + 예외** | 차단 시도가 증적화되어야 OQ 통과 |
| 3 | 감사기록은 **DB 트리거 + 애플리케이션 이중 기록** | 데이터 변경 자체 + 사용자 맥락 |
| 4 | Odoo-Nextcloud는 **FastAPI 중계형** | 전 문서 행위를 감사추적에 포함 |
| 5 | Nextcloud는 협업, **MinIO Object Lock이 규제 보존** | 보존 계층 명확 분리 |
| 6 | MinIO는 **COMPLIANCE 모드 + IAM DeleteObject 거부** | Object Lock만으로 Delete Marker 방지 불가 |
| 7 | DSS는 **3-step + PAdES_BASELINE_LT 이상** | 공식 API 구조, 장기 검증 가능성 |
| 8 | 서명 의미는 **commitmentTypeIndications + 가시 서명란** | §11.50(a)(3), (b) |
| 9 | 검증 전략은 **CSV 형식주의가 아닌 CSA 위험 기반** | FDA CSA 최종 가이던스가 GPSV §6 대체 |
| 10 | RAG 접근제어는 **저장소 필터 + 앱 재필터 이중화** | `in` 연산자 동작의 저장소 의존성 |
| 11 | 임베딩은 **bge-m3 계열 (1024d)** | 한국어 SOP 검색 필수 |
| 12 | RAG 답변은 **품질 판단 아님** — UI·SOP 명시 | 최종 해석·승인은 담당자 책임 |
| 13 | UDI는 **기록·보고파일 생성까지** 범위 | 공식 연계 API 미확인, 질의 후 확장 |
| 14 | 규제 자동 영향도 평가는 **초안**, QA 승인 후 재검증 개시 | 키워드 판정의 오탐·미탐 |

---

## 14. 잔여 불확실성

> v1.0의 6개 항목 중 4개는 §0.4에서 해소했다. 아래는 외부 확인이 필요한 잔여 항목이다.

| 항목 | 내용 | 확인 방법 | 기한 |
|---|---|---|---|
| 공급내역 연계 규격 | 통합정보시스템의 외부 연계 API 존재 여부 | 의료기기통합정보센터 1899-9351 질의 | Phase 0 |
| 사내 CA 운영 | 서명 인증서 발급·갱신·폐기 주체 및 절차 | 정보보안 담당 협의 | Phase 0 |
| FDA 비부인 서한 | 제출 대상 여부 및 양식 | 규제담당 + FDA 안내 확인 | Phase 2 |
| 기록 보존기간 | 제품별 법정 보존기간 (Object Lock 기간 결정 입력값) | 규제담당 확정 | Phase 1 |
| 한국어 LLM 모델 | Ollama 운용 가능 범위 내 최적 모델 | PQ-003 벤치마크 | Phase 4 |
| AGPL-3.0 영향 | QAtrial 채택 시 공개 의무 범위 | 법무 검토 | Phase 0 (채택 시) |

---

## 15. 출처

### 공식 1차 출처 (2026-10-11 직접 확인)

1. [21 CFR Part 820 — Quality Management System Regulation (eCFR)](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-H/part-820)
2. [21 CFR Part 11 — Electronic Records; Electronic Signatures (eCFR)](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)
3. [FDA — Quality Management System Regulation (QMSR)](https://www.fda.gov/medical-devices/postmarket-requirements-devices/quality-management-system-regulation-qmsr)
4. [FDA — QMSR Frequently Asked Questions](https://www.fda.gov/medical-devices/quality-management-system-regulation-qmsr/quality-management-system-regulation-frequently-asked-questions)
5. [Federal Register — Computer Software Assurance for Production and Quality System Software (Final Guidance, 2025-09-24)](https://www.federalregister.gov/api/v1/documents/2025-18468.json)
6. [EU DSS — Webservices (REST/SOAP) Cookbook](https://github.com/esig/dss/blob/master/dss-cookbook/src/main/asciidoc/_chapters/webservices.adoc)
7. [EU DSS — getDataToSign 요청 샘플](https://github.com/esig/dss/blob/master/dss-cookbook/src/main/asciidoc/_restdocs/sign-and-extend-one-document/1/curl-request.adoc)
8. [EU DSS — validateSignature 요청·응답 샘플](https://github.com/esig/dss/blob/master/dss-cookbook/src/main/asciidoc/_restdocs/validate-doc/1/response-body.adoc)
9. [Haystack — Metadata Filtering](https://docs.haystack.deepset.ai/docs/metadata-filtering)
10. [Haystack — ChatMessage (.content → .text, 2.9 변경)](https://docs.haystack.deepset.ai/docs/chatmessage)
11. [Haystack — OllamaChatGenerator](https://docs.haystack.deepset.ai/docs/ollamachatgenerator)
12. [BAAI/bge-m3 모델 사양 (1024차원, 8192토큰, 다국어)](https://build.nvidia.com/baai/bge-m3/modelcard)
13. [MinIO — Object Locking and Immutability](https://docs.min.io/aistor/administration/object-locking-and-immutability/)
14. [NSF — FDA Final Guidance Computer Software Assurance (2026-02-03 개정 안내)](https://www.nsf.org/life-science-regulatory-news/fda-final-guidance-computer-software-assurance-csa)
15. [식약처 — 의료기기 통합정보 등록 및 공급내역 보고 민원상담 사례집 개정 (2026-08-19)](https://eiec.kdi.re.kr/policy/materialView.do?num=285518)

### 사내 조사자료 (2차)

G-Research.md, P-eQMS-01 ~ P-eQMS-10 — 상용 솔루션 비교, 오픈소스 후보, 스키마·템플릿 초안. **§0에 기재된 오류 항목은 본 계획서의 수정본을 따른다.**

---

**승인**

| 역할 | 성명 | 서명 | 일자 |
|---|---|---|---|
| 작성자 | | | |
| 검토자 (QA Owner) | | | |
| 승인자 (System Owner) | | | |
