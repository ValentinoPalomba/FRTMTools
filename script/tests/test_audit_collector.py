"""Regression checks for audit classification, redaction and archive extraction."""
import json
import pathlib
import tempfile
import types
import unittest
import zipfile

SOURCE=pathlib.Path(__file__).resolve().parents[2]/'FRTMToolsCLI/AuditCollector.swift'
engine=types.ModuleType('audit_engine')
exec(SOURCE.read_text().split('static let source = #"""\n',1)[1].rsplit('\n"""#',1)[0],engine.__dict__)

class AuditCollectorTests(unittest.TestCase):
 def test_jwt_is_redacted_and_expiry_is_checked(self):
  import base64
  payload=base64.urlsafe_b64encode(json.dumps({'exp':1,'email':'private@example.com'}).encode()).rstrip(b'=')
  token=b'eyJhbGciOiJIUzI1NiJ9.'+payload+b'.abcdefghijk'
  result=engine.scan(token,'mock.json')
  self.assertTrue(result['secret_candidates'][0]['expired'])
  self.assertNotIn(token.decode(),json.dumps(result))
  self.assertNotIn('private@example.com',json.dumps(result))
 def test_maven_coordinate_mapping_ignores_unknown_versions(self):
  result=engine.maven_packages([{'path':'META-INF/androidx.appcompat_appcompat.version','content':'1.6.1'},{'path':'x.properties','content':'version=unknown'}])
  self.assertEqual(result,[{'package':{'name':'androidx.appcompat:appcompat','ecosystem':'Maven'},'version':'1.6.1','evidence':'META-INF/androidx.appcompat_appcompat.version'}])
 def test_zip_traversal_rejected(self):
  with tempfile.TemporaryDirectory() as temporary:
   root=pathlib.Path(temporary);archive=root/'input.zip'
   with zipfile.ZipFile(archive,'w') as z:z.writestr('../escaped.txt','forbidden')
   with self.assertRaisesRegex(RuntimeError,'Unsafe archive path'):engine.safe_extract(archive,root/'extracted')
   self.assertFalse((root/'escaped.txt').exists())
 def test_debug_certificate_does_not_imply_debuggable(self):
  with tempfile.TemporaryDirectory() as temporary:
   engine.OUT=pathlib.Path(temporary)
   d={'platform':'Android','label':'test','manifest':{'application':{}},'native':[], 'signing':{'exit':0,'stdout':'CN=Android Debug','stderr':''},'scan':[]}
   findings=engine.findings(d,[])
   self.assertEqual([x['id'] for x in findings],['SIGNING'])
 def test_fixed_nanopb_not_flagged_by_presence(self):
  with tempfile.TemporaryDirectory() as temporary:
   engine.OUT=pathlib.Path(temporary)
   d={'platform':'iOS','label':'test','info':{},'frameworks':[{'name':'nanopb.framework','version':'0.4.9.2'}],'signing':{'exit':0,'stdout':'','stderr':''},'signature_verification':{'exit':0,'stdout':'','stderr':''},'scan':[]}
   self.assertEqual(engine.findings(d,[]),[])

 def test_mock_directory_at_bundle_root_is_detected_once(self):
  with tempfile.TemporaryDirectory() as temporary:
   engine.OUT=pathlib.Path(temporary)
   d={'platform':'Android','label':'test','manifest':{'application':{}},'native':[], 'signing':{'exit':0,'stdout':'','stderr':''},'scan':[]}
   result=engine.findings(d,[{'path':'mock/mock.json','bytes':2},{'path':'mock/patch.json','bytes':2}])
   self.assertEqual(len(result),1)
   self.assertEqual(result[0]['id'],'MOCK')
   self.assertEqual(result[0]['origin'],'cli')
   self.assertIn('mock/patch.json',result[0]['evidence'])

if __name__=='__main__':unittest.main()
