#!/usr/bin/env bash
# 4-5: 직접 만든 GGUF를 Modelfile로 Ollama에 등록하고, 템플릿 유무·파라미터 차이를 같은 질문으로 확인한다.
# 사용: OUT=<ch04 출력 디렉터리> [OLLAMA_HOST=127.0.0.1:11434] bash register_ch04.sh
set -u
OUT=${OUT:?ch04 출력 디렉터리}; NAME=${NAME:-Qwen3.5-4B}; MF=$OUT/modelfiles; mkdir -p "$MF"; cd "$MF"
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}
log(){ echo "[$(date +%H:%M:%S)] $*"; }
Q='리눅스 서버에서 /var 파티션 사용률이 95%입니다. 원인을 찾는 절차를 3단계로, 각 단계에 명령 한 줄씩 붙여 답하세요.'

create(){ local alias=$1 mf=$2; ollama list | grep -qE "^$alias(:| )" && { log "exists $alias"; return; }
  log "create $alias"; local t0=$(date +%s); ollama create "$alias" -f "$mf" > "create-$alias.log" 2>&1 || { log "  FAILED: $(tail -1 create-$alias.log)"; return; }
  log "  $(( $(date +%s) - t0 ))s, $(grep -oE "(using existing|copying|creating) [a-z ]*layer sha256:[0-9a-f]{12}" create-$alias.log | tail -1)"; }
ask(){ # ask <alias> <label> [think:true|false]
  local alias=$1 label=$2 think=${3:-true}
  curl -s "http://$OLLAMA_HOST/api/chat" -d "{\"model\":\"$alias\",\"stream\":false,\"think\":$think,\"messages\":[{\"role\":\"user\",\"content\":\"$Q\"}],\"options\":{\"temperature\":0,\"num_predict\":700}}" > "chat-$label.json"
  python3 - "chat-$label.json" "$label" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); m=d.get('message',{})
if 'error' in d: print(f"{sys.argv[2]}: ERROR {d['error']}"); sys.exit()
th=m.get('thinking') or ''; c=m.get('content','')
print(f"{sys.argv[2]}: done_reason={d.get('done_reason')} thinking={len(th)}자 content={len(c)}자 eval={d.get('eval_count')}tok {d.get('eval_count',0)/max(d.get('eval_duration',1),1)*1e9:.1f}tok/s load={d.get('load_duration',0)/1e9:.1f}s")
print("   content:", c[:500].replace('\n',' | '))
PY
}
show(){ ollama show "$1" | grep -E "architecture|parameters|context length|quantization|Capabilities|tools|thinking|completion|System|Parameters" | tr -s ' ' | tr '\n' ';' ; echo; ollama show "$1" --modelfile | grep -E "^(TEMPLATE|PARAMETER|SYSTEM|RENDERER|PARSER)" | cut -c1-80; }

# 1) FROM만 있는 Modelfile: 템플릿과 파라미터를 Ollama가 어떻게 채우는지 본다
printf 'FROM %s/%s-Q4_K_M.gguf\n' "$OUT" "$NAME" > bare.Modelfile
create ch04-q4km-bare bare.Modelfile; show ch04-q4km-bare
curl -s "http://$OLLAMA_HOST/api/show" -d '{"model":"ch04-q4km-bare"}' | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('template',''); print('  template source:', 'GGUF Jinja' if t.startswith('{%') else repr(t[:60])); print('  capabilities:', d.get('capabilities'))"
ask ch04-q4km-bare bare-think true
ask ch04-q4km-bare bare-nothink false

# 2) 템플릿을 잘못 넣은 경우: 채팅 표식 없는 TEMPLATE로 덮어쓴다
printf 'FROM %s/%s-Q4_K_M.gguf\nTEMPLATE """{{ .Prompt }}"""\n' "$OUT" "$NAME" > badtmpl.Modelfile
create ch04-q4km-badtmpl badtmpl.Modelfile; show ch04-q4km-badtmpl
ask ch04-q4km-badtmpl badtmpl true

# 3) 이 책의 권장 Modelfile: 문맥·온도·시스템 프롬프트 고정
cat > q4km.Modelfile <<MF
FROM $OUT/$NAME-Q4_K_M.gguf
PARAMETER num_ctx 16384
PARAMETER temperature 0
SYSTEM 당신은 리눅스 서버 운영을 돕는 엔지니어링 보조입니다. 확인되지 않은 사실은 단정하지 말고, 명령은 한 줄씩 제시합니다.
MF
create ch04-q4km q4km.Modelfile; show ch04-q4km
ask ch04-q4km q4km-nothink false

# 4) 비교용: 다른 타입도 같은 방식으로 등록 (4-4의 GPU 속도 비교에 사용)
for tag in Q8_0 IQ3_XXS IQ2_XXS; do a=ch04-$(echo "$tag" | tr 'A-Z_' 'a-z-')
  printf 'FROM %s/%s-%s.gguf\nPARAMETER num_ctx 16384\nPARAMETER temperature 0\n' "$OUT" "$NAME" "$tag" > "$a.Modelfile"; create "$a" "$a.Modelfile"; done
ollama list | grep ch04
log REGISTER_DONE
