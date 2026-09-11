#!/usr/bin/env bash
# 10장: 27B 원본을 BF16 GGUF로 변환하고, 업무 데이터 imatrix와 텐서별 정밀도 지정으로 12GB·24GB 목표 양자화본을 만든다. CPU만 사용.
# 사용: LLAMA=<llama.cpp> MODEL_DIR=<Qwen3.8-27B 원본> OUT=<출력> CALIB=<캘리브레이션 텍스트> bash run_ch10.sh [단계]
#   단계: convert | imatrix | quant | all (기본 all). 완료된 산출물은 건너뜀.
# 자원: RAM 64GB 이상, 디스크 원본 54GB + BF16 54GB + 양자화본(각 9~15GB). 원본은 BF16 변환 후 지워도 됨.
set -euo pipefail
LLAMA=${LLAMA:?}; MODEL_DIR=${MODEL_DIR:?}; OUT=${OUT:?}; CALIB=${CALIB:?}
STEP=${1:-all}; BIN=$LLAMA/build/bin; THREADS=${THREADS:-$(nproc)}
mkdir -p "$OUT"; cd "$OUT"; NAME=$(basename "$MODEL_DIR")
log(){ echo "[$(date +%F' '%H:%M:%S)] $*"; }
t(){ local s=$(date +%s.%N); "$@"; python3 -c "import sys,time; print('  elapsed %.0fs' % (time.time()-float(sys.argv[1])))" "$s"; }

if [[ $STEP == convert || $STEP == all ]]; then
  [ -f "$NAME-bf16.gguf" ] || { log "convert 27B to BF16 (RAM 64GB+)"; t python3 "$LLAMA/convert_hf_to_gguf.py" "$MODEL_DIR" --outtype bf16 --outfile "$NAME-bf16.gguf" > convert.log 2>&1; }
  ls -l --block-size=G "$NAME-bf16.gguf" | awk '{print $5,$9}'
fi

if [[ $STEP == imatrix || $STEP == all ]]; then
  # 업무 데이터 imatrix: 문맥 512, 청크 수는 캘리브레이션 텍스트 크기에 맞춤(100~200 권장)
  [ -f imatrix-work.gguf ] || { log "imatrix from work data ($CALIB)"; t "$BIN/llama-imatrix" -m "$NAME-bf16.gguf" -f "$CALIB" -o imatrix-work.gguf -c 512 --chunks ${CHUNKS:-128} -t "$THREADS" > imatrix.log 2>&1; }
fi

if [[ $STEP == quant || $STEP == all ]]; then
  quant(){ local tag=$1 type=$2; shift 2; [ -f "$NAME-$tag.gguf" ] && return; log "quantize $tag ($type $*)"
    if ! t "$BIN/llama-quantize" "$@" "$NAME-bf16.gguf" "$NAME-$tag.gguf" "$type" > "quantize-$tag.log" 2>&1; then
      log "  FAILED $tag: $(grep -m1 -E "failed to quantize:" "quantize-$tag.log" | cut -c1-160)"; rm -f "$NAME-$tag.gguf"; fi; }
  # 27B의 마지막 층 blk.64는 MTP(다음 토큰 예측)층으로 추론에 쓰이지 않아 imatrix 항목이 없다. 4장과 같이 이 층만 타입을 고정한다.
  MTP="--tensor-type blk\.${MTP_BLK:-64}\.=q8_0"
  # 12GB 목표: 가중치 10GB 안팎. 비교용 기본형과 텐서별 보호형
  quant work-IQ2_XS         IQ2_XS  --imatrix imatrix-work.gguf $MTP
  quant work-IQ3_XXS        IQ3_XXS --imatrix imatrix-work.gguf $MTP
  quant work-IQ3_XXS-protect IQ3_XXS --imatrix imatrix-work.gguf --token-embedding-type q8_0 --output-tensor-type q6_k --tensor-type attn_v=q5_k --tensor-type ffn_down=q4_k $MTP
  # 24GB 목표: 문맥 여유를 남기는 IQ4
  quant work-IQ4_XS         IQ4_XS  --imatrix imatrix-work.gguf $MTP
  # 공개 imatrix와 비교하려면 IMATRIX_PUBLIC=<파일> 지정
  if [ -n "${IMATRIX_PUBLIC:-}" ]; then quant public-IQ3_XXS IQ3_XXS --imatrix "$IMATRIX_PUBLIC" $MTP; fi
  ls -l --block-size=M "$NAME"-*.gguf | awk '{print $5,$9}' | tee sizes.txt
fi
log DONE
