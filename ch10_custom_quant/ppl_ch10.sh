#!/usr/bin/env bash
# 10장: 만들어진 양자화본과 BF16의 퍼플렉시티를 같은 텍스트로 비교(CUDA 빌드, GPU 적재). wikitext-2 test 40청크 + 업무 캘리브레이션 텍스트(편향 확인용).
# 사용: LLAMA=<llama.cpp> OUT=<ch10 출력> WIKI=<wiki.test.raw> [NGL=99] bash ppl_ch10.sh
set -u
LLAMA=${LLAMA:?}; OUT=${OUT:?}; WIKI=${WIKI:?}; NAME=${NAME:-Qwen3.8-27B}; BIN=$LLAMA/build/bin; cd "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*"; }
ppl(){ local f=$1 txt=$2 tag=$3 chunks=$4; [ -f "ppl-$tag.txt" ] && return; log "perplexity $tag"
  "$BIN/llama-perplexity" -m "$f" -f "$txt" -c 512 --chunks "$chunks" -ngl "${NGL:-99}" > "ppl-$tag.txt" 2>&1 || true
  grep -E "Final estimate" "ppl-$tag.txt" | tail -1; }
for f in "$NAME"-*.gguf; do tag=${f#$NAME-}; tag=${tag%.gguf}
  ppl "$f" "$WIKI" "wiki-$tag" 40
  [ -f calib-work.txt ] && ppl "$f" calib-work.txt "calib-$tag" 40
done
grep -H "Final estimate" ppl-*.txt | sed 's/ppl-\(.*\).txt:.*PPL = /\1 /' | tee ppl.txt
log PPL_DONE
