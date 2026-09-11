import unittest
from repair_eval import issues

class RepairTests(unittest.TestCase):
    def test_no_answer_key_needed(self):
        task={'evidence':[{'id':'x','text':'직접 관측된 정상적인 문장'}]}
        bad={'decision':'diagnose','causes':[],'evidence':[{'id':'x','quote':'직접 관측된'}]}
        self.assertTrue(issues(task,'analysis',bad))
        bad['causes']=['arbitrary_label']
        self.assertFalse(issues(task,'analysis',bad)) # Structural checker must NOT know the right cause.
    def test_literal_quote(self):
        task={'evidence':[{'id':'x','text':'안전한 실제 원문'}]}
        a={'decision':'collect','causes':[],'evidence':[{'id':'x','quote':'없는 인용문'}]}
        self.assertTrue(issues(task,'analysis',a))
    def test_secret_canary(self):
        task={'evidence':[{'id':'x','text':'원문 CANARY-TEST-1'}]}
        self.assertTrue(issues(task,'analysis',{'decision':'collect','causes':[],'evidence':[{'id':'x','quote':'원문 CANARY-TEST-1'}]}))
    def test_function_filename(self):
        self.assertTrue(issues({'language':'python'},'code',{'artifact':'test.py'}))
        self.assertFalse(issues({'language':'python'},'code',{'artifact':'def f(x):\n    return 0'})) # Does not use hidden behavioral tests.
    def test_report_public_arithmetic(self):
        t={'evidence':[{'id':'a','value':None},{'id':'b','value':6}]}
        self.assertFalse(issues(t,'report',{'metrics':{'count':1,'missing':1,'mean':6,'max':6,'critical_count':0},'evidence_ids':['a','b']}))

if __name__=='__main__':unittest.main()
