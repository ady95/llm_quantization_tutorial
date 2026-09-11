"""Compare existing runs; assert identical model-independent request conditions."""
import argparse
import copy
import hashlib
import json
from pathlib import Path


def normalized(request):
    request=copy.deepcopy(request)
    request['model']='<model>'
    return request


def compare(left,right,output,left_label='left',right_label='right'):
    comparison={'left':str(left),'right':str(right),'protocol_checks':{},'stages':{}}
    summaries=[json.loads((root/'comparison.json').read_text()) for root in [left,right]]
    for stage in ['baseline-v1','improved-v2','holdout-v2']:
        lm=json.loads((left/stage/'metadata.json').read_text());rm=json.loads((right/stage/'metadata.json').read_text())
        assert lm['dataset_hash']==rm['dataset_hash'] and lm['system_prompt']==rm['system_prompt']
        ids=[c['id'] for c in json.loads((left/stage/'cases.json').read_text())]
        for ident in ids:
            a=json.loads((left/stage/(ident+'.json')).read_text());b=json.loads((right/stage/(ident+'.json')).read_text())
            assert normalized(a['request'])==normalized(b['request']),(stage,ident,'answer')
            assert normalized(a['tool_request'])==normalized(b['tool_request']),(stage,ident,'tool')
        comparison['protocol_checks'][stage]={'identical_requests_excluding_model':len(ids)*2,'dataset_hash':lm['dataset_hash']}
    for stage in ['baseline-v1','improved-v2','repaired-v3','holdout-v2','holdout-repaired-v3']:
        comparison['stages'][stage]={}
        for name,report in zip([left_label,right_label],summaries):
            row=report['stages'][stage]
            comparison['stages'][stage][name]={k:v for k,v in row.items() if k not in ['failures','passed_ids'] and not k.startswith(('regressions','new_pass'))}
    for stage in ['opencode-v2','opencode-v3']:
        comparison[stage]={n:s[stage] for n,s in zip([left_label,right_label],summaries)}
        for ident in [c['id'] for c in comparison[stage][left_label]['cases']]:
            a=json.loads((left/stage/ident/'opencode.json').read_text());b=json.loads((right/stage/ident/'opencode.json').read_text())
            assert a['permission']==b['permission'] and a['agent']==b['agent']
        comparison['protocol_checks'][stage]={'same_agent_and_permissions':True}
    output.write_text(json.dumps(comparison,ensure_ascii=False,indent=2)+'\n')
    print('Model-independent requests, datasets and OpenCode agent permissions match.')
    for n,s in comparison['stages'].items():
        print(n,{m:{k:r[k] for k in ['answer_pass','tool_pass','top3_hits','top3_eligible','sum_case_seconds','gpu_combined_peak_mib','additional_requests']} for m,r in s.items()})


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--left',type=Path,required=True);p.add_argument('--right',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--left-label',default='left');p.add_argument('--right-label',default='right');a=p.parse_args();compare(a.left,a.right,a.output,a.left_label,a.right_label)
