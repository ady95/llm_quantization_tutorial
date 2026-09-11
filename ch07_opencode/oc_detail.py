import json,os,sys,csv
base=sys.argv[1]
ev_ids={e["id"]:e["text"] for e in json.load(open(f"{base}/workspace/input.json",encoding="utf-8"))["evidence"]}
for a in sorted(os.listdir(f"{base}/runs")):
    out=f"{base}/runs/{a}"
    if not os.path.isdir(out): continue
    ev=[]
    for line in open(f"{out}/events.jsonl",encoding="utf-8",errors="replace"):
        line=line.strip()
        if line:
            try: ev.append(json.loads(line))
            except: pass
    tools=[];toks=[];texts=[]
    for e in ev:
        p=e.get("part") or {}
        if p.get("type")=="tool": tools.append(p.get("tool"))
        if p.get("type")=="step-finish": toks.append((p["tokens"]["input"],p["tokens"]["output"]))
        if p.get("type")=="text": texts.append(p.get("text","")[:200].replace("\n"," "))
    rows=[r for r in csv.DictReader(open(f"{out}/vram.csv")) if r.get("mem_used_mib","").strip().isdigit()]
    vm=max(int(r["mem_used_mib"]) for r in rows) if rows else None
    ans=f"{out}/ws/answer.json"; d=None; err=None
    if os.path.exists(ans):
        try: d=json.load(open(ans,encoding="utf-8"))
        except Exception as ex: err=str(ex)
    print(f"===== {a} | wall≈{len(rows)}s | vram {vm} | steps {len(toks)} | tools {tools}")
    print("  tokens(in,out):",toks)
    if d:
        print("  verdict:",d.get("verdict"),"| n_causes:",len(d.get("causes",[])),"| n_actions:",len(d.get("actions",[])))
        for c in d.get("causes",[]):
            q=c.get("quote","") or ""; ids=c.get("evidence_ids",[]) or []
            exact=any(q and q in ev_ids.get(i,"") for i in ids) if q else None
            print(f"   - ids={ids} quote_exact={exact} cause={c.get('cause','')[:60]}")
    else:
        print("  answer.json:", "MISSING" if err is None else f"INVALID {err}")
    for t in texts[:2]: print("  text:",t[:160])
