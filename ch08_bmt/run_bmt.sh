#!/usr/bin/env bash
# 8장 엔지니어링 BMT 전체 절차. 사용: bash run_bmt.sh <ollama 모델 별칭> <결과 루트 디렉터리>
#   예: BMT_OLLAMA_PORT=11434 bash run_bmt.sh qwen3.8:27b ../results/q4km
# 순서: 채점기 점검 → v1 기본 → v2 개선 → v3 보정 → 추가 사례 v2·v3 → OpenCode 파일 작업(보완 전·후) → 요약
# 같은 GPU에 다른 모델이 적재되어 있으면 평가기가 중단합니다(자원 측정 오염 방지).
set -euo pipefail
MODEL=${1:?모델 별칭}; OUT=${2:?결과 루트}
cd "$(dirname "$0")"
mkdir -p "$OUT"
python3 check_grader.py
python3 check_repair.py
python3 bmt_eval.py --model "$MODEL" --profile baseline --output "$OUT/baseline-v1"
python3 bmt_eval.py --model "$MODEL" --profile improved --output "$OUT/improved-v2"
python3 repair_eval.py --source "$OUT/improved-v2" --output "$OUT/repaired-v3"
python3 bmt_eval.py --model "$MODEL" --profile improved --dataset holdout.json --output "$OUT/holdout-v2"
python3 repair_eval.py --source "$OUT/holdout-v2" --output "$OUT/holdout-repaired-v3"
python3 opencode_e2e.py --model "$MODEL" --legacy-file-prompt --output "$OUT/opencode-v2"
python3 opencode_e2e.py --model "$MODEL" --output "$OUT/opencode-v3"
python3 summarize_eval.py --root "$OUT"
echo "완료: $OUT/comparison.json"
