"""Deterministic grader regression tests; no model calls."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from bmt_eval import grade, grade_code, grade_tool, schema, valid

CASES=json.loads((Path(__file__).parent/'cases.json').read_text())

class GraderTests(unittest.TestCase):
    def test_korean_http_utf8(self):
        from bmt_eval import api
        with patch('bmt_eval.http.client.HTTPConnection') as factory:
            response=factory.return_value.getresponse.return_value
            response.status=200;response.read.return_value=b'{}'
            api('/api/chat',{'message':'한국어'})
            body=factory.return_value.request.call_args.args[2]
            self.assertIsInstance(body,bytes)
            self.assertEqual(json.loads(body.decode('utf-8')),{'message':'한국어'})
    def test_good_and_invented_evidence(self):
        c=CASES[0];answer={'decision':'diagnose','causes':['disk_full'],'evidence':[{'id':'e1','quote':c['input']['evidence'][0]['text']}],'explanation':'공간이 소진됨'}
        response=lambda a:{'message':{'content':json.dumps(a)}}
        self.assertTrue(grade(c,response(answer))['passed'])
        answer['evidence'][0]['id']='invented';self.assertFalse(grade(c,response(answer))['passed'])
    def test_wrong_cause(self):
        c=CASES[0];a={'decision':'diagnose','causes':['memory_oom'],'evidence':[{'id':'e1','quote':c['input']['evidence'][0]['text']}],'explanation':'오답'}
        self.assertFalse(grade(c,{'message':{'content':json.dumps(a)}})['top3_hit'])
    def test_invalid_schema(self):
        self.assertFalse(valid({'artifact':'pass','extra':1},schema(CASES[50])))
        self.assertFalse(valid(True,{'type':'number'}))
    def test_python_good_bad_and_import(self):
        c=CASES[50];checks=c['expected']['checks']
        self.assertTrue(grade_code('def classify(value):\n    return "unknown" if value is None else "critical" if value >= 90 else "normal"','python',checks)['passed'])
        self.assertFalse(grade_code('def classify(value):\n    return "normal"','python',checks)['passed'])
        self.assertFalse(grade_code('import os\ndef classify(value):\n    return "normal"','python',checks)['policy'])
    def test_shell_not_executed(self):
        c=CASES[54];check=c['expected']['checks']
        self.assertTrue(grade_code('#!/bin/bash\nset -eu\n'+check['command'],'bash',check)['passed'])
        self.assertFalse(grade_code('set -eu\n'+check['command']+'\nrm -rf /tmp/x','bash',check)['passed'])
    def test_safe_list_append(self):
        c=CASES[51];check=c['expected']['checks']
        source='def missing(required, observed):\n    result = []\n    for item in required:\n        if item not in observed:\n            result.append(item)\n    return result'
        self.assertTrue(grade_code(source,'python',check)['passed'])
        self.assertFalse(grade_code('def missing(required, observed):\n    return required.__class__','python',check)['policy'])
    def test_tools(self):
        c=CASES[0];f={'name':c['expected']['tool'],'arguments':c['expected']['tool_args']}
        self.assertTrue(grade_tool(c,{'message':{'tool_calls':[{'function':f}]}})['passed'])
        f['arguments']=dict(f['arguments'],host_id='unauthorized');self.assertFalse(grade_tool(c,{'message':{'tool_calls':[{'function':f}]}})['passed'])
        c=next(c for c in CASES if c['expected']['tool'] is None)
        self.assertTrue(grade_tool(c,{'message':{}})['passed'])
        self.assertFalse(grade_tool(c,{'message':{'tool_calls':[{'function':f}]}})['passed'])
    def test_report(self):
        c=CASES[70];a={k:c['expected'][k] for k in ['metrics','evidence_ids']}
        self.assertTrue(grade(c,{'message':{'content':json.dumps(a)}})['passed'])
        a['metrics']=dict(a['metrics'],mean=999);self.assertFalse(grade(c,{'message':{'content':json.dumps(a)}})['passed'])

if __name__=='__main__':unittest.main()
