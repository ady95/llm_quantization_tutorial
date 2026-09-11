#!/usr/bin/env bash
# 4장: 소형 원본 모델(Qwen3.5-4B)을 GGUF로 변환하고 여러 타입으로 양자화해 크기·퍼플렉시티·속도를 비교한다. CPU만 사용.
# 사용: LLAMA=<llama.cpp 디렉터리> MODEL_DIR=<HF 원본 디렉터리> OUT=<출력 디렉터리> bash run_ch04.sh
set -euo pipefail
LLAMA=${LLAMA:?llama.cpp 디렉터리}; MODEL_DIR=${MODEL_DIR:?원본 모델 디렉터리}; OUT=${OUT:?출력 디렉터리}
BIN=$LLAMA/build/bin; mkdir -p "$OUT"; cd "$OUT"
NAME=$(basename "$MODEL_DIR")
log(){ echo "[$(date +%H:%M:%S)] $*"; }
t(){ local s=$(date +%s.%N); "$@"; python3 -c "import sys,time; print('  elapsed %.1fs' % (time.time()-float(sys.argv[1])))" "$s"; }

# 1) HF → BF16 GGUF
if [ ! -f "$NAME-bf16.gguf" ]; then log "convert to BF16"; t python3 "$LLAMA/convert_hf_to_gguf.py" "$MODEL_DIR" --outtype bf16 --outfile "$NAME-bf16.gguf" > convert.log 2>&1; fi

# 2) 캘리브레이션 텍스트: 이 책의 평가 사례(합성 서버 업무 텍스트)와 프롬프트 — 업무 분포에 가까운 예시
if [ ! -f calib.txt ]; then
  python3 - "$(dirname "$0")/../ch08_bmt" <<'PY' > calib.txt
import json,sys
root=sys.argv[1]
for f in ["cases.json","holdout.json"]:
    for c in json.load(open(f"{root}/{f}",encoding="utf-8")):
        i=c["input"]; print(i.get("task",""))
        for e in i.get("evidence",[]): print(e.get("text",""))
        print()
print(open(f"{root}/prompt_v2.txt",encoding="utf-8").read())
PY
  wc -c calib.txt
fi

# 3) imatrix (CPU, 문맥 512)
if [ ! -f imatrix.gguf ]; then log "imatrix"; t "$BIN/llama-imatrix" -m "$NAME-bf16.gguf" -f calib.txt -o imatrix.gguf -c 512 --chunks 64 -t 24 > imatrix.log 2>&1; fi

# 4) 양자화: 균일 K-quants, 조합 K-quants, --pure, I-quants(imatrix)
quant(){ local type=$1 tag=$2; shift 2; [ -f "$NAME-$tag.gguf" ] && return; log "quantize $tag"; t "$BIN/llama-quantize" "$@" "$NAME-bf16.gguf" "$NAME-$tag.gguf" "$type" > "quantize-$tag.log" 2>&1; }
quant Q8_0   Q8_0
quant Q4_K_M Q4_K_M
quant Q4_K_M Q4_K_M-pure --pure
quant Q4_K_S Q4_K_S
quant Q2_K   Q2_K
quant IQ4_XS IQ4_XS --imatrix imatrix.gguf
quant IQ3_XXS IQ3_XXS --imatrix imatrix.gguf
quant IQ2_XXS IQ2_XXS --imatrix imatrix.gguf
quant IQ2_XXS IQ2_XXS-noimatrix

# 5) 크기 표
ls -l --block-size=M *.gguf | awk '{print $5, $9}' | tee sizes.txt

# 6) 퍼플렉시티 (같은 텍스트, 문맥 512, 16청크, CPU)
for f in "$NAME"-*.gguf; do tag=${f#$NAME-}; tag=${tag%.gguf}; [ -f "ppl-$tag.txt" ] && continue; log "perplexity $tag"; "$BIN/llama-perplexity" -m "$f" -f calib.txt -c 512 --chunks 16 -t 24 > "ppl-$tag.txt" 2>&1 || true; grep -E "Final estimate|estimate:" "ppl-$tag.txt" | tail -1; done
grep -H "Final estimate" ppl-*.txt | sed 's/ppl-\(.*\).txt:.*PPL = /\1 /' | tee ppl.txt
log DONE
