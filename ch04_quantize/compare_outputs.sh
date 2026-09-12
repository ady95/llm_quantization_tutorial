#!/usr/bin/env bash
# 4-4: 모든 양자화본(BF16 포함)을 Ollama에 등록하고 같은 질문에 사고 끔(think:false)으로 답하게 해 출력을 나란히 본다.
# 사용: OUT=<ch04 출력 디렉터리> [OLLAMA_HOST=...] bash compare_outputs.sh
set -u
OUT=${OUT:?}; NAME=${NAME:-Qwen3.5-4B}; MF=$OUT/modelfiles; RES=$OUT/compare; mkdir -p "$MF" "$RES"
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}
log(){ echo "[$(date +%H:%M:%S)] $*"; }
Q='다음 로그를 보고 원인을 한 문장으로 판정하고, 확인 명령 한 줄을 제시하세요.\n[로그] kernel: Out of memory: Killed process 21877 (api-server) total-vm:8123456kB, anon-rss:6102400kB\n[로그] systemd: api.service: Main process exited, code=killed, status=9/KILL'
TAGS=${TAGS:-"bf16 Q8_0 Q4_K_M Q4_K_S Q4_K_M-pure IQ4_XS IQ3_XXS Q2_K IQ2_XXS"}
alias_of(){ echo "ch04-$(echo "$1" | tr 'A-Z_' 'a-z-')"; }
for t in $TAGS; do a=$(alias_of "$t"); ollama list | grep -qE "^$a(:| )" && continue
  printf 'FROM %s/%s-%s.gguf\nPARAMETER num_ctx 16384\nPARAMETER temperature 0\n' "$OUT" "$NAME" "$t" > "$MF/$a.Modelfile"
  log "create $a"; ollama create "$a" -f "$MF/$a.Modelfile" > "$MF/create-$a.log" 2>&1 || log "  FAILED $(tail -1 "$MF/create-$a.log")"; done
for t in $TAGS; do a=$(alias_of "$t")
  # 이전 모델 내리기
  for m in $(curl -s "http://$OLLAMA_HOST/api/ps" | python3 -c "import json,sys; print(' '.join(x['name'] for x in json.load(sys.stdin)['models']))"); do curl -s "http://$OLLAMA_HOST/api/generate" -d "{\"model\":\"$m\",\"keep_alive\":0}" >/dev/null; done
  for i in 1 2; do
    curl -s "http://$OLLAMA_HOST/api/chat" -d "{\"model\":\"$a\",\"stream\":false,\"think\":false,\"messages\":[{\"role\":\"user\",\"content\":\"$Q\"}],\"options\":{\"temperature\":0,\"num_predict\":200}}" > "$RES/$t-$i.json"
  done
  python3 - "$RES/$t-1.json" "$RES/$t-2.json" "$t" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); w=json.load(open(sys.argv[2])); t=sys.argv[3]; ns=1e9
if 'error' in d: print(t, 'ERROR', d['error']); sys.exit()
print(f"### {t}: load={d.get('load_duration',0)/ns:.1f}s warm eval={w.get('eval_count')}tok {w.get('eval_count',0)/max(w.get('eval_duration',1),1)*ns:.1f}tok/s done={w.get('done_reason')}")
print(d['message']['content'].strip()[:700])
PY
  curl -s "http://$OLLAMA_HOST/api/ps" | python3 -c "import json,sys; [print('  vram=%dMiB'%(x['size_vram']//2**20), x['name']) for x in json.load(sys.stdin)['models']]"
done
log COMPARE_DONE
