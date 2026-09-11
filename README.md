# LLM 양자화 따라하기 — 예제 코드

위키독스 책 「LLM 양자화 따라하기 (12GB·24GB GPU로 Qwen 기반 나만의 엔지니어링 에이전트 만들기)」의 예제 코드와 평가 데이터입니다.

- 책: https://wikidocs.net/book/21323
- 기준 버전: Ollama 0.34, OpenCode 1.18, Python 3.10 이상
- 실습 모델: Qwen 3.8 27B (Ollama 기본 태그 Q4_K_M, Unsloth UD-IQ3_XXS, ISTA-DASLab GSQ-RCO-IQ3_XXS, AtomicChat AD-IQ2_XS)

## 구성

| 디렉터리 | 책의 장 | 내용 |
|---|---|---|
| `ch02_first_run/` | 2장, 6장 | `bmt_tools.sh` — 첫 실행 기록(`first_run`), nvidia-smi 1초 표본 수집(`vram_sample_start/stop`) |
| `ch06_settings/` | 6장 | `start_ollama_instance.sh` — 환경 변수 실험용 사용자 권한 Ollama 인스턴스 |
| `ch07_opencode/` | 7장 | `opencode.json`(격리 설정), `run_task.sh`(파일 과제 실행기), `workspace/input.json`(과제), `oc_detail.py`(결과 분석) |
| `ch08_bmt/` | 8장, 9장 | 엔지니어링 BMT: 데이터(`cases.json` 100개, `holdout.json` 20개), 평가기, 보정기, OpenCode 파일 작업 평가, 채점기 자기 점검, 요약·비교 |

## 빠른 시작

```bash
pip install -r requirements.txt

# 채점기 자기 점검 (모델 호출 없음)
cd ch08_bmt
python check_grader.py
python check_repair.py

# 고정 업무 평가 (localhost Ollama, 다른 모델이 적재되어 있으면 중단됨)
python bmt_eval.py --model qwen3.8:27b --profile baseline --output ../results/q4km/baseline-v1
python bmt_eval.py --model qwen3.8:27b --profile improved --output ../results/q4km/improved-v2
python repair_eval.py --source ../results/q4km/improved-v2 --output ../results/q4km/repaired-v3
```

전체 절차(추가 사례, OpenCode 파일 작업, 요약)는 `ch08_bmt/run_bmt.sh`에 있습니다. 다른 포트의 Ollama 인스턴스를 쓰려면 `BMT_OLLAMA_PORT` 환경 변수를 지정합니다.

## 데이터와 재현 원칙

- `ch08_bmt/cases.json`, `holdout.json`은 모두 합성 데이터입니다. 실제 시스템·고객 정보와 무관하며, 비밀값처럼 보이는 문자열(`CANARY-*`)은 재출력 검사를 위한 가짜입니다.
- `dataset-manifest.json`의 SHA-256과 일치하지 않으면 평가기가 실행을 거부합니다. 데이터를 수정하지 마세요. 독자의 새 검증 세트는 별도 파일로 만듭니다(책 9-4).
- 평가기는 모델이 생성한 도구·셸을 절대 실행하지 않습니다. Python 코드 산출물은 제한된 AST와 별도 프로세스에서 순수 함수만 검사합니다.
- 결과 디렉터리는 덮어쓰지 않습니다(이미 있으면 중단). 요약·비교 스크립트는 원본 결과를 수정하지 않습니다.

## 실측 기록

책의 실측에 쓴 배포본의 저장소 revision, 파일 SHA-256, Ollama 블롭 digest는 책 5-1과 `RECORDS.md`에 있습니다.

## 라이선스

(집필 중. 공개 전 확정)
