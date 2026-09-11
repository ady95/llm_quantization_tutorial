#!/usr/bin/env bash
# 실측 보조 도구. 사용: source bmt_tools.sh 후 함수 호출, 또는 bash bmt_tools.sh <cmd> ...
# 환경변수: OLLAMA_HOST (기본 127.0.0.1:11434), GPU_IDX (nvidia-smi -i, 기본 전체)

: "${OLLAMA_HOST:=127.0.0.1:11434}"

vram_sample_start() {  # vram_sample_start <out.csv>
  local out="$1"
  echo "ts,gpu,mem_used_mib,mem_total_mib,util_pct,power_w" > "$out"
  ( while true; do
      nvidia-smi ${GPU_IDX:+-i} ${GPU_IDX:-} --query-gpu=timestamp,index,memory.used,memory.total,utilization.gpu,power.draw --format=csv,noheader,nounits \
        | sed 's/, /,/g' >> "$out"; sleep 1; done ) &
  echo $! > "$out.pid"
}
vram_sample_stop() {  # vram_sample_stop <out.csv>
  kill "$(cat "$1.pid")" 2>/dev/null; rm -f "$1.pid"
  python3 - "$1" <<'EOF'
import csv,sys
rows=[r for r in csv.DictReader(open(sys.argv[1])) if r.get('mem_used_mib') and r['mem_used_mib'].strip().isdigit()]
by={}
for r in rows: by.setdefault(r['gpu'],[]).append(r)
for g,rs in by.items():
    used=[int(float(r['mem_used_mib'])) for r in rs]
    print(f"GPU{g}: samples={len(rs)} mem_used min={min(used)} max={max(used)} MiB (total {rs[0]['mem_total_mib']})")
EOF
}

api() { curl -s "http://$OLLAMA_HOST$1" "${@:2}"; }

first_run() {  # first_run <model> <outdir> [prompt]
  local model="$1" out="$2" prompt="${3:-서버의 디스크 사용량을 확인하는 리눅스 명령을 한 줄로 알려 주세요.}"
  mkdir -p "$out"
  echo "== ollama version ==" | tee "$out/summary.txt"; api /api/version | tee -a "$out/summary.txt"; echo | tee -a "$out/summary.txt"
  echo "== ollama show ==" | tee -a "$out/summary.txt"
  OLLAMA_HOST=$OLLAMA_HOST ollama show "$model" | tee "$out/show.txt" | head -40 >> "$out/summary.txt"
  OLLAMA_HOST=$OLLAMA_HOST ollama show "$model" --modelfile > "$out/modelfile.txt" 2>/dev/null
  api /api/show -d "{\"model\":\"$model\"}" > "$out/api_show.json"
  vram_sample_start "$out/vram.csv"
  echo "== generate (cold) ==" | tee -a "$out/summary.txt"
  local t0=$(date +%s.%N)
  api /api/chat -d "{\"model\":\"$model\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"options\":{\"temperature\":0}}" > "$out/chat_cold.json"
  local t1=$(date +%s.%N)
  python3 - "$out/chat_cold.json" "$t0" "$t1" <<'EOF' | tee -a "$out/summary.txt"
import json,sys
d=json.load(open(sys.argv[1])); wall=float(sys.argv[3])-float(sys.argv[2])
ns=1e9
print(f"wall={wall:.1f}s load={d.get('load_duration',0)/ns:.1f}s prompt_eval={d.get('prompt_eval_count')}tok/{d.get('prompt_eval_duration',0)/ns:.2f}s eval={d.get('eval_count')}tok/{d.get('eval_duration',0)/ns:.2f}s => {d.get('eval_count',0)/(d.get('eval_duration',1)/ns):.1f} tok/s")
print("answer:", d['message']['content'][:300].replace('\n',' '))
EOF
  echo "== /api/ps ==" | tee -a "$out/summary.txt"; api /api/ps | python3 -m json.tool | tee "$out/ps.json" | grep -E '"(name|size|size_vram|context_length|quantization_level|parameter_size)"' | tee -a "$out/summary.txt"
  echo "== generate (warm) ==" | tee -a "$out/summary.txt"
  t0=$(date +%s.%N)
  api /api/chat -d "{\"model\":\"$model\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"options\":{\"temperature\":0}}" > "$out/chat_warm.json"
  t1=$(date +%s.%N)
  python3 - "$out/chat_warm.json" "$t0" "$t1" <<'EOF' | tee -a "$out/summary.txt"
import json,sys
d=json.load(open(sys.argv[1])); wall=float(sys.argv[3])-float(sys.argv[2]); ns=1e9
print(f"wall={wall:.1f}s load={d.get('load_duration',0)/ns:.2f}s prompt_eval={d.get('prompt_eval_count')}tok eval={d.get('eval_count')}tok/{d.get('eval_duration',0)/ns:.2f}s => {d.get('eval_count',0)/(d.get('eval_duration',1)/ns):.1f} tok/s")
EOF
  sleep 2; echo "== VRAM samples ==" | tee -a "$out/summary.txt"; vram_sample_stop "$out/vram.csv" | tee -a "$out/summary.txt"
  echo "== nvidia-smi now ==" | tee -a "$out/summary.txt"; nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader | tee -a "$out/summary.txt"
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader | tee -a "$out/summary.txt"
}

"$@"
