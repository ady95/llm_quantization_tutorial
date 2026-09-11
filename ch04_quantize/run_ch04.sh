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
#    실패해도 체인을 멈추지 않고 로그에 남긴다(부분 파일은 삭제). 실패 로그 자체가 관찰 대상이다.
quant(){ local type=$1 tag=$2; shift 2; [ -f "$NAME-$tag.gguf" ] && return; log "quantize $tag"
  if ! t "$BIN/llama-quantize" "$@" "$NAME-bf16.gguf" "$NAME-$tag.gguf" "$type" > "quantize-$tag.log" 2>&1; then
    log "  FAILED $tag: $(grep -m1 -E "failed to quantize:" "quantize-$tag.log" | cut -c1-160)"; rm -f "$NAME-$tag.gguf"; fi; }
quant Q8_0   Q8_0
quant Q4_K_M Q4_K_M
quant Q4_K_M Q4_K_M-pure --pure
quant Q4_K_S Q4_K_S
quant Q2_K   Q2_K
quant IQ4_XS IQ4_XS --imatrix imatrix.gguf
# 마지막 층(blk.32)은 다음 토큰 예측(MTP)층으로 추론에 실행되지 않아 imatrix 항목이 없다. 이 층 없이 IQ3/IQ2를 만들면
# "Missing importance matrix for tensor blk.32..." 오류로 중단되므로(quantize-IQ3_XXS-failed.log) 그 층만 타입을 고정한다.
MTP='--tensor-type blk\.32\.=q8_0'
quant IQ3_XXS IQ3_XXS --imatrix imatrix.gguf $MTP
quant IQ2_XXS IQ2_XXS --imatrix imatrix.gguf $MTP
quant IQ2_XXS IQ2_XXS-noimatrix $MTP            # imatrix 없는 IQ2: 실패가 예상되는 대조 실험

# 5) 크기 표
ls -l --block-size=M *.gguf | awk '{print $5, $9}' | tee sizes.txt

# 6) 퍼플렉시티: (a) 캘리브레이션 텍스트(imatrix에 쓴 것과 같아 I-quants에 유리한 편향) (b) 분리된 텍스트 wikitext-2 test
#    wikitext-2: eval/wiki.test.raw 가 있으면 사용. https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip
ppl(){ local f=$1 txt=$2 tag=$3 chunks=$4; [ -f "ppl-$tag.txt" ] && return; log "perplexity $tag"
  "$BIN/llama-perplexity" -m "$f" -f "$txt" -c 512 --chunks "$chunks" -t ${THREADS:-24} > "ppl-$tag.txt" 2>&1 || true
  grep -E "Final estimate" "ppl-$tag.txt" | tail -1; }
for f in "$NAME"-*.gguf; do tag=${f#$NAME-}; tag=${tag%.gguf}
  ppl "$f" calib.txt "$tag" 16
  [ -f eval/wiki.test.raw ] && ppl "$f" eval/wiki.test.raw "wiki-$tag" 40
done
grep -H "Final estimate" ppl-*.txt | sed 's/ppl-\(.*\).txt:.*PPL = / /' | tee ppl.txt

# 7) 같은 프롬프트에 대한 생성 결과(greedy) — 눈으로 비교하기 위한 표본
mkdir -p gen
GENPROMPT='다음 로그를 보고 원인을 한 문장으로 판정하고, 확인 명령 한 줄을 제시하세요.
[로그] kernel: Out of memory: Killed process 21877 (api-server) total-vm:8123456kB, anon-rss:6102400kB
[로그] systemd: api.service: Main process exited, code=killed, status=9/KILL
답:'
for f in "$NAME"-*.gguf; do tag=${f#$NAME-}; tag=${tag%.gguf}; [ -f "gen/$tag.txt" ] && continue; log "generate $tag"
  "$BIN/llama-completion" -m "$f" -p "$GENPROMPT" -n 120 --temp 0 -no-cnv -t ${THREADS:-24} --no-warmup 2> "gen/$tag.err" | tail -c 1500 > "gen/$tag.txt" || true
  grep -E "eval time|prompt eval" "gen/$tag.err" | sed 's/^/  /' | cut -c1-120; done
log DONE
