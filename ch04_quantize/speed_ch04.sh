#!/usr/bin/env bash
# 4-4: 등록한 양자화본들의 GPU 생성 속도·적재 시간·GPU 메모리를 같은 요청으로 비교한다(thinking 끔, 256토큰, 3회).
# 사용: [OLLAMA_HOST=127.0.0.1:11434] [MODELS="ch04-q8-0 ch04-q4km ch04-iq3-xxs ch04-iq2-xxs"] bash speed_ch04.sh <outdir>
set -u
OUT=${1:?출력 디렉터리}; mkdir -p "$OUT"; export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}
MODELS=${MODELS:-"ch04-q8-0 ch04-q4km ch04-iq3-xxs ch04-iq2-xxs"}
P='리눅스 서버에서 디스크 사용률 90% 경보가 왔을 때의 대응 절차를 10단계로, 각 단계에 명령 한 줄씩 붙여 설명해 주세요.'
for m in $MODELS; do
  curl -s "http://$OLLAMA_HOST/api/generate" -d '{"model":"'"$m"'","keep_alive":0}' >/dev/null   # 이전 모델 내리기
  for i in 1 2 3; do
    curl -s "http://$OLLAMA_HOST/api/chat" -d "{\"model\":\"$m\",\"stream\":false,\"think\":false,\"messages\":[{\"role\":\"user\",\"content\":\"$P\"}],\"options\":{\"temperature\":0,\"num_predict\":256,\"num_ctx\":16384}}" > "$OUT/$m-$i.json"
    python3 - "$OUT/$m-$i.json" "$m" "$i" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); ns=1e9
if 'error' in d: print(sys.argv[2], sys.argv[3], 'ERROR', d['error']); sys.exit()
print(f"{sys.argv[2]} run{sys.argv[3]}: load={d.get('load_duration',0)/ns:.1f}s prompt={d.get('prompt_eval_count')}tok/{d.get('prompt_eval_duration',0)/ns:.2f}s eval={d.get('eval_count')}tok/{d.get('eval_duration',0)/ns:.2f}s => {d.get('eval_count',0)/max(d.get('eval_duration',1),1)*ns:.1f} tok/s")
PY
  done
  curl -s "http://$OLLAMA_HOST/api/ps" | python3 -c "import json,sys; [print('  ps:',x['name'],'size=%dMiB'%(x['size']//2**20),'vram=%dMiB'%(x['size_vram']//2**20)) for x in json.load(sys.stdin)['models']]"
  nvidia-smi --query-gpu=index,memory.used --format=csv,noheader | sed 's/^/  gpu: /'
done
echo SPEED_DONE
