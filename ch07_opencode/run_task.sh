#!/usr/bin/env bash
# 사용: bash run_task.sh <alias> ; 격리된 XDG/OPENCODE 설정으로 lab 에이전트 실행
set -u
cd "$(dirname "$0")"
A=$1; OUT=$PWD/runs/$A; rm -rf $OUT; mkdir -p $OUT/xdg $OUT/ws; cp workspace/input.json $OUT/ws/
export PATH=$HOME/.opencode/bin:$PATH
export XDG_CONFIG_HOME=$OUT/xdg/config XDG_DATA_HOME=$OUT/xdg/data XDG_CACHE_HOME=$OUT/xdg/cache XDG_STATE_HOME=$OUT/xdg/state
python3 -c "import json,sys; c=json.load(open('opencode.json')); c['model']=c['small_model']='ollama-local/'+sys.argv[1]; json.dump(c,open(sys.argv[2],'w'),ensure_ascii=False,indent=1)" $A $OUT/opencode.json
export OPENCODE_CONFIG=$OUT/opencode.json OPENCODE_CONFIG_DIR=$OUT/xdg/config-dir
for k in OPENCODE_DISABLE_AUTOUPDATE OPENCODE_DISABLE_MODELS_FETCH OPENCODE_DISABLE_DEFAULT_PLUGINS OPENCODE_DISABLE_EXTERNAL_SKILLS OPENCODE_DISABLE_CLAUDE_CODE OPENCODE_DISABLE_PROJECT_CONFIG OPENCODE_DISABLE_LSP_DOWNLOAD OPENCODE_DISABLE_SHARE; do export $k=1; done
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434} GPU_IDX=${GPU_IDX:-0}
source "$(dirname "$0")/../ch02_first_run/bmt_tools.sh"
# 모델 미리 적재(콜드 제외)
api /api/chat -d "{\"model\":\"$A\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" >/dev/null
vram_sample_start $OUT/vram.csv
cd $OUT/ws
T0=$(date +%s.%N)
timeout 600 opencode --pure run --agent lab --format json -m ollama-local/$A "이 디렉터리의 input.json을 읽고, request 필드의 지시에 따라 같은 디렉터리에 answer.json을 작성하세요." > ../events.jsonl 2> ../stderr.txt
RC=$?
T1=$(date +%s.%N)
cd "$(dirname "$0")"
sleep 2; vram_sample_stop $OUT/vram.csv > $OUT/vram_summary.txt
python3 - $OUT "$T0" "$T1" $RC <<PY
import json,sys,os
out,t0,t1,rc=sys.argv[1],float(sys.argv[2]),float(sys.argv[3]),sys.argv[4]
ev=[]; 
for line in open(f"{out}/events.jsonl",encoding="utf-8",errors="replace"):
    line=line.strip()
    if not line: continue
    try: ev.append(json.loads(line))
    except Exception: pass
types={}
tools=[]
for e in ev:
    t=e.get("type") or e.get("event") or "?"
    types[t]=types.get(t,0)+1
    p=e.get("part") or e.get("properties",{}).get("part") or {}
    if isinstance(p,dict) and p.get("type")=="tool": tools.append(p.get("tool"))
ans=os.path.join(out,"ws","answer.json"); ok=os.path.exists(ans)
valid=None
if ok:
    try: d=json.load(open(ans,encoding="utf-8")); valid=all(k in d for k in ("verdict","causes","actions"))
    except Exception as ex: valid=f"parse-error {ex}"
print(json.dumps({"alias":os.path.basename(out),"rc":rc,"wall_s":round(t1-t0,1),"events":len(ev),"event_types":types,"tool_calls":tools,"answer_exists":ok,"answer_valid":valid,"vram":open(f"{out}/vram_summary.txt").read().strip()},ensure_ascii=False))
if ok: print("ANSWER:",open(ans,encoding="utf-8").read()[:600])
PY
