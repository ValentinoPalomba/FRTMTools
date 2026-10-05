import pathlib,types,unittest
SOURCE=pathlib.Path(__file__).resolve().parents[2]/'FRTMToolsCLI/AuditCollector.swift'
engine=types.ModuleType('audit_engine')
exec(SOURCE.read_text().split('static let source = #"""\n',1)[1].rsplit('\n"""#',1)[0],engine.__dict__)
def fixture():
 return {'input':'Example.app','platform':'iOS','audit_date':'2026-10-01','info':{'CFBundleIdentifier':'org.example','CFBundleExecutable':'Example','CFBundleShortVersionString':'1.0','CFBundleVersion':'1'},'signing':{'stdout':'','stderr':''},'signature_verification':{'exit':127},'main_macho':{},'frameworks':[],'categories':{'other':400},'largest_files':[{'path':'Example','bytes':300,'category':'other'}],'uncompressed_bytes':400,'file_count':2,'duplicate_redundant_bytes':0,'duplicates':[]}
class ReportStandardTests(unittest.TestCase):
 def test_unobtainable_sections_and_measurements_are_omitted(self):
  model=engine.standard_platform(fixture(),[{'path':'Example','bytes':300}],[],{},[])
  self.assertEqual(model['schemaVersion'],'1.3')
  self.assertFalse({'deadCode','dynamicModules','excludedAdvisories'} & {b['key'] for b in model['blocks']})
  for key in ['packageBytes','installEstimate','downloadEstimate']:self.assertNotIn(key,model['summary'])
  self.assertEqual(sum(model['summary']['checks'].values()),len(model['checks']))
 def test_chart_categories_do_not_count_main_twice(self):
  model=engine.standard_platform(fixture(),[{'path':'Example','bytes':300}],[],{},[])
  self.assertEqual(sum(x['bytes'] for x in model['charts']['categories']),400)
  self.assertIn({'name':'Codice principale','bytes':300},model['charts']['categories'])
 def test_curated_advisory_exclusions_are_omitted(self):
  d=fixture();d['frameworks']=[{'name':'nanopb.framework','version':'3.30910.0','build':'1','bytes':10}]
  model=engine.standard_platform(d,[],[],{},[])
  self.assertNotIn('excludedAdvisories',[x['key'] for x in model['blocks']])
 def test_failed_verification_is_not_presented_as_a_finding(self):
  model=engine.standard_platform(fixture(),[],[],{},[])
  self.assertFalse(any(x['check']=='Firma bundle' for x in model['checks']))
 def test_manual_findings_do_not_enter_reports(self):
  finding={'id':'SEC-02','title':'Manual grant flow','cwe':'CWE-732','severity':'Alta','evidence':'JADX manual flow','fix':'Review'}
  model=engine.standard_platform(fixture(),[],[finding],{},[])
  self.assertEqual(model['summary']['findings'],0)
  self.assertFalse(next(x for x in model['blocks'] if x['key']=='assessment')['rows'])
 def test_json_in_script_is_escaped(self):
  model=engine.standard_platform(fixture(),[],[],{},[])
  result=engine.standard_html('</script><script>alert(1)</script>',{'ios':model})
  self.assertNotIn('</script><script>alert(1)',result)
  self.assertIn('\\u003c/script',result)
 def test_localization_is_omitted_from_collected_and_cached_models(self):
  d=fixture();d['localizations']=['en','it','fr']
  model=engine.standard_platform(d,[],[],{},[])
  self.assertNotIn('localization',[b['key'] for b in model['blocks']])
  model['blocks'].append({'key':'localization','title':'Traduzioni obsolete','headers':['Lingua'],'rows':[['fr']],'note':''})
  result=engine.standard_html('Example',{'ios':model})
  import re,json
  data=json.loads(re.search(r'const DATA=(.*?);</script>',result,re.S).group(1))
  self.assertNotIn('localization',[b['key'] for b in data['platforms']['ios']['blocks']])
  self.assertNotIn('Traduzioni obsolete',result)
 def test_row_column_alignment(self):
  model=engine.standard_platform(fixture(),[],[],{},[])
  for block in model['blocks']:
   for row in block['rows']:self.assertEqual(len(row),len(block['headers']),block['key'])
if __name__=='__main__':unittest.main()
