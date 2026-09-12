#!/usr/bin/env bash
# 4-5 보조 실험: GGUF에 들어 있는 채팅 템플릿(tokenizer.chat_template)을 지운 사본을 만들어,
# Modelfile의 TEMPLATE가 없을 때·틀렸을 때·맞을 때 응답이 어떻게 달라지는지 본다.
# 사용: OUT=<ch04 출력 디렉터리> LLAMA=<llama.cpp> [OLLAMA_HOST=...] bash template_experiment.sh
set -u
OUT=${OUT:?}; LLAMA=${LLAMA:?}; NAME=${NAME:-Qwen3.5-4B}; MF=$OUT/modelfiles; mkdir -p "$MF"; cd "$MF"
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}
log(){ echo "[$(date +%H:%M:%S)] $*"; }
Q='리눅스 서버에서 /var 파티션 사용률이 95%입니다. 원인을 찾는 절차를 3단계로, 각 단계에 명령 한 줄씩 붙여 답하세요.'
SRC=$OUT/$NAME-Q4_K_M.gguf; NOT=$OUT/$NAME-Q4_K_M-notmpl.gguf
[ -f "$NOT" ] || { log "strip chat_template"; python3 "$LLAMA/gguf-py/gguf/scripts/gguf_new_metadata.py" "$SRC" "$NOT" --remove-metadata tokenizer.chat_template --force > strip.log 2>&1 || tail -2 strip.log; }
create(){ local alias=$1 mf=$2; ollama list | grep -qE "^$alias(:| )" && { log "exists $alias"; return; }; log "create $alias"; ollama create "$alias" -f "$mf" > "create-$alias.log" 2>&1 || log "  FAILED: $(tail -1 create-$alias.log)"; }
ask(){ local alias=$1 label=$2 think=${3:-false}
  curl -s "http://$OLLAMA_HOST/api/chat" -d "{\"model\":\"$alias\",\"stream\":false,\"think\":$think,\"messages\":[{\"role\":\"user\",\"content\":\"$Q\"}],\"options\":{\"temperature\":0,\"num_predict\":300}}" > "chat-$label.json"
  python3 - "chat-$label.json" "$label" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); m=d.get('message',{})
if 'error' in d: print(f"{sys.argv[2]}: ERROR {d['error']}"); sys.exit()
c=m.get('content',''); print(f"{sys.argv[2]}: done_reason={d.get('done_reason')} eval={d.get('eval_count')}tok content={len(c)}자")
print("   ", c[:600].replace('\n',' | '))
PY
}
tmpl(){ curl -s "http://$OLLAMA_HOST/api/show" -d "{\"model\":\"$1\"}" | python3 -c "import json,sys; t=json.load(sys.stdin).get('template',''); print('   template used:', repr(t[:90]))"; }

printf 'FROM %s\n' "$NOT" > notmpl-bare.Modelfile
cat > notmpl-alpaca.Modelfile <<MF
FROM $NOT
TEMPLATE """### Instruction:
{{ .Prompt }}

### Response:
"""
MF
cat > notmpl-chatml.Modelfile <<MF
FROM $NOT
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{- range .Messages }}<|im_start|>{{ .Role }}
{{ .Content }}<|im_end|>
{{ end }}<|im_start|>assistant
"""
PARAMETER stop <|im_end|>
MF
# 내장 렌더러·파서 지정: 템플릿 없는 GGUF에 이 책이 권하는 방식
printf 'FROM %s
RENDERER qwen3.5
PARSER qwen3.5
' "$NOT" > notmpl-renderer.Modelfile
for v in bare alpaca chatml renderer; do create ch04-notmpl-$v notmpl-$v.Modelfile; tmpl ch04-notmpl-$v; ask ch04-notmpl-$v notmpl-$v false; done
log TEMPLATE_DONE
