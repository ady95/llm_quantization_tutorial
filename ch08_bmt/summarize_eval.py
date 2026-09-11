"""Build comparison evidence without overwriting any original run results."""
import argparse
import hashlib
import json
from pathlib import Path
from bmt_eval import grade, summarize

parser=argparse.ArgumentParser();parser.add_argument('--skip-baseline',action='store_true');parser.add_argument('--root',type=Path,required=True);ARGS=parser.parse_args();ROOT=ARGS.root
report={'stages':{},'sources':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(__file__).resolve().parent.glob('*.py') if p.is_file()}}
for name in ['baseline-v1','improved-v2','repaired-v3','holdout-v2','holdout-repaired-v3']:
    if name=='baseline-v1' and ARGS.skip_baseline:continue
    folder=ROOT/name;cases=json.loads((folder/'cases.json').read_text());records=[];corrections=[]
    for case in cases:
        r=json.loads((folder/(case['id']+'.json')).read_text());g=grade(case,r.get('response',{}))
        if r.get('response',{}).get('done_reason')=='length':g['passed']=False;g['errors'].append('truncated')
        if g!=r['grade']:corrections.append({'id':case['id'],'original':r['grade'],'corrected':g})
        r['grade']=g;records.append(r)
    s=summarize(records)
    (folder/'summary-regraded.json').write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n')
    (folder/'grader-corrections.json').write_text(json.dumps(corrections,ensure_ascii=False,indent=2)+'\n')
    s['json_schema_valid']=sum(r['grade'].get('schema_valid',False) for r in records)
    noncode=[r for r,c in zip(records,cases) if c['kind']!='code']
    s['evidence_checked_cases']=len(noncode);s['evidence_pass']=sum(r['grade'].get('grounded',False) for r in noncode)
    s['additional_requests']=sum(bool(r.get('repair',{}).get(k)) for r in records for k in ['answer','tool'])
    s['answer_repairs']=sum(r.get('repair',{}).get('answer',False) for r in records)
    s['tool_repairs']=sum(r.get('repair',{}).get('tool',False) for r in records)
    s['sum_case_seconds']=round(sum(r['elapsed_seconds'] for r in records),3)
    s['extra_seconds']=round(sum(r.get('repair',{}).get('additional_elapsed_seconds',0) for r in records),3)
    peaks={};totals=[]
    for sample in json.loads((folder/'gpu-samples.json').read_text()):
        total=0
        for line in sample.get('gpu','').splitlines():
            fields=[x.strip() for x in line.split(',')];mem=float(fields[1]);peaks[fields[0]]=max(peaks.get(fields[0],0),mem);total+=mem
        totals.append(total)
    s['gpu_peak_mib']=peaks;s['gpu_combined_peak_mib']=max(totals,default=0)
    s['passed_ids']=[r['id'] for r in records if r['grade']['passed']]
    s['graded_source_hash']=report['sources']['tests/evaluation/bmt_eval.py']
    report['stages'][name]=s
for previous,current in [('baseline-v1','improved-v2'),('improved-v2','repaired-v3')]:
    if previous not in report['stages']:continue
    a=set(report['stages'][previous]['passed_ids']);b=set(report['stages'][current]['passed_ids'])
    report['stages'][current]['regressions_from_'+previous]=sorted(a-b)
    report['stages'][current]['new_pass_from_'+previous]=sorted(b-a)
for name in ['opencode-v2','opencode-v3']:
    p=ROOT/name/'summary.json'
    if p.exists():
        rows=json.loads(p.read_text());report[name]={'completed':len(rows),'passed':sum(r['passed'] for r in rows),'cases':rows}
(ROOT/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for n,s in report['stages'].items():
    print(n,{k:s[k] for k in ['answer_pass','tool_pass','top3_hits','top3_eligible','evidence_pass','evidence_checked_cases','additional_requests','answer_repairs','tool_repairs','sum_case_seconds','extra_seconds','gpu_combined_peak_mib']})
