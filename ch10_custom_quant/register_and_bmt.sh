#!/usr/bin/env bash
# 10장: run_ch10.sh 가 만든 양자화본을 Ollama에 등록하고 8장 BMT(v2 개선 프롬프트 + v3 보정)로 재검증한다.
# 사용: OUT=<ch10 출력> RESULTS=<결과 루트> [OLLAMA_HOST=...] [TAGS="work-IQ3_XXS ..."] bash register_and_bmt.sh
set -u
OUT=${OUT:?}; RESULTS=${RESULTS:?}; NAME=${NAME:-Qwen3.8-27B}
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}; export BMT_OLLAMA_PORT=${OLLAMA_HOST##*:}
HERE=$(cd "$(dirname "$0")" && pwd); BMT=$HERE/../ch08_bmt
TAGS=${TAGS:-"work-IQ2_XS work-IQ3_XXS work-IQ3_XXS-protect work-IQ4_XS public-IQ3_XXS"}
log(){ echo "[$(date +%H:%M:%S)] $*"; }
for t in $TAGS; do f=$OUT/$NAME-$t.gguf; [ -f "$f" ] || { log "skip $t (no file)"; continue; }
  a=ch10-$(echo "$t" | tr 'A-Z_' 'a-z-')
  ollama list | grep -qE "^$a(:| )" || { printf 'FROM %s\nPARAMETER num_ctx 16384\nPARAMETER temperature 0\n' "$f" > "$OUT/$a.Modelfile"; log "create $a"; ollama create "$a" -f "$OUT/$a.Modelfile" > "$OUT/create-$a.log" 2>&1 || { log "  FAILED"; continue; }; }
  R=$RESULTS/$a; mkdir -p "$R"; cd "$BMT"
  [ -d "$R/improved-v2" ] || { log "bmt v2 $a"; python3 bmt_eval.py --model "$a" --profile improved --output "$R/improved-v2" > "$R/v2.log" 2>&1 || log "  v2 failed: $(tail -1 "$R/v2.log")"; }
  [ -d "$R/repaired-v3" ] || { log "bmt v3 $a"; python3 repair_eval.py --source "$R/improved-v2" --output "$R/repaired-v3" > "$R/v3.log" 2>&1 || log "  v3 failed: $(tail -1 "$R/v3.log")"; }
  [ -d "$R/holdout-v2" ] || { log "holdout $a"; python3 bmt_eval.py --model "$a" --profile improved --dataset holdout.json --output "$R/holdout-v2" > "$R/holdout.log" 2>&1 && python3 repair_eval.py --source "$R/holdout-v2" --output "$R/holdout-repaired-v3" >> "$R/holdout.log" 2>&1 || log "  holdout failed"; }
  if [ "${OPENCODE:-0}" = 1 ]; then [ -d "$R/opencode-v3" ] || { log "opencode $a"; python3 opencode_e2e.py --model "$a" --output "$R/opencode-v3" > "$R/opencode.log" 2>&1 || log "  opencode failed"; }; fi
  python3 summarize_eval.py --root "$R" > "$R/summary.txt" 2>&1; tail -4 "$R/summary.txt" | cut -c1-200; cd - >/dev/null
done
log BMT10_DONE
