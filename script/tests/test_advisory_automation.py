"""Range, provenance and bytecode checks for the automatic audit."""
import pathlib,types,unittest
from unittest.mock import patch
SOURCE=pathlib.Path(__file__).resolve().parents[2]/'FRTMToolsCLI/AuditCollector.swift'
engine=types.ModuleType('engine')
exec(SOURCE.read_text().split('static let source = #"""\n',1)[1].rsplit('\n"""#',1)[0],engine.__dict__)
def advisory(range='<= 0.4.9.1',name='nanopb'):
 return {'ghsa_id':'GHSA-test-test-test','severity':'high','summary':'Candidate','cwes':[{'cwe_id':'CWE-674'}],'vulnerabilities':[{'package':{'name':name},'vulnerable_version_range':range,'patched_versions':'0.4.9.2'}]}
class AdvisoryAutomationTests(unittest.TestCase):
 def test_stable_range_boundaries_and_branches(self):
  self.assertTrue(engine.version_in_range('0.3.9.10','<= 0.4.9.1'))
  self.assertFalse(engine.version_in_range('0.3.9.10','>= 0.4.0, <= 0.4.9.1'))
  self.assertTrue(engine.version_in_range('0.3.9.6','>= 0.3.2, < 0.3.9.8 || >= 0.4.0, < 0.4.5'))
  self.assertFalse(engine.version_in_range('0.4.9.2','<= 0.4.9.1'))
 def test_unsupported_versions_and_ranges_stay_unknown(self):
  self.assertIsNone(engine.version_in_range('0.4.9.2-beta','<= 0.4.9.1'))
  self.assertIsNone(engine.version_in_range('0.3.9.10','~0.3.9'))
  self.assertIsNone(engine.version_in_range('3.30910.0',None))
 def test_official_podspec_converts_version_without_guessing(self):
  spec={'status':200,'data':{'name':'nanopb','version':'3.30910.0','source':{'git':'https://github.com/nanopb/nanopb.git','tag':'0.3.9.10'}}}
  with patch.object(engine,'request',return_value=spec) as fetch:
   result=engine.resolve_pod('nanopb','3.30910.0',{})
  self.assertEqual(result['upstream'],'0.3.9.10')
  self.assertIn('/6/1/e/nanopb/3.30910.0/',fetch.call_args[0][0])
 def test_wrong_repository_or_missing_spec_does_not_normalize(self):
  spec={'status':200,'data':{'name':'nanopb','version':'3.30910.0','source':{'git':'https://github.com/unrelated/repo.git','tag':'0.3.9.10'}}}
  with patch.object(engine,'request',return_value=spec):self.assertIsNone(engine.resolve_pod('nanopb','3.30910.0',{})['upstream'])
  with patch.object(engine,'request',return_value={'status':'unavailable'}):self.assertIsNone(engine.resolve_pod('nanopb','3.30910.0',{})['upstream'])
 def test_placeholder_and_offline_do_not_fetch(self):
  with patch.object(engine,'request') as fetch:
   self.assertIsNone(engine.resolve_pod('nanopb','1.0.0',{})['upstream'])
   self.assertIsNone(engine.resolve_pod('nanopb','3.30910.0',{},True)['upstream'])
   fetch.assert_not_called()
 def test_match_exclude_and_unresolved_are_distinct(self):
  dependency={'installed':'3.30910.0','resolution':{'upstream':'0.3.9.10','evidence':'podspec'},'advisories':{'data':[advisory(),advisory('>= 0.4.0, <= 0.4.9.1'),advisory(name='unrelated')]}}
  records=engine.match_repository('nanopb',dependency)
  self.assertEqual([x['state'] for x in records],['affected','excluded','unknown'])
  self.assertEqual(records[0]['cwes'],['CWE-674'])
  self.assertEqual(records[0]['patch'],'0.4.9.2')
 def test_withdrawn_advisory_is_not_a_finding(self):
  a=advisory();a['withdrawn_at']='2026-01-01'
  self.assertEqual(engine.match_repository('nanopb',{'advisories':{'data':[a]}}),[])
 def test_pagination_collects_next_page(self):
  pages=[{'status':200,'data':[advisory()],'next':'<https://api.github.com/page2>; rel="next"'},{'status':200,'data':[],'next':''}]
  with patch.object(engine,'request',side_effect=pages) as fetch:r=engine.repository_advisories('nanopb/nanopb',{})
  self.assertTrue(r['complete']);self.assertEqual(len(r['data']),1);self.assertEqual(fetch.call_count,2)
 def test_partial_fetch_is_not_a_success(self):
  with patch.object(engine,'request',return_value={'status':'unavailable','error':'rate limit'}):r=engine.repository_advisories('nanopb/nanopb',{})
  self.assertFalse(r['complete']);self.assertEqual(r['status'],'unavailable')
 def test_json_personal_fields_never_include_values(self):
  result=engine.json_personal_fields(b'{"account":{"email":"private@example.com","firstName":"Private"}}')
  self.assertEqual(result,['account.email','account.firstName']);self.assertNotIn('private@example.com',str(result))
 def test_grant_argument_is_obtained_from_actual_instruction(self):
  code='.method public share()V\nconst/4 v7, 0x3\ninvoke-virtual {v6, v4, v2, v7}, Landroid/content/Context;->grantUriPermission(Ljava/lang/String;Landroid/net/Uri;I)V\n.end method'
  self.assertEqual(engine.smali_grants(code)[0]['grants'][0]['flags'],3)
  self.assertEqual(engine.smali_grants(code.replace('0x3','0x1')),[])
  self.assertEqual(engine.smali_grants(code.replace('invoke-virtual',' :label\ninvoke-virtual')),[])
 def test_automatic_exclusions_are_displayed(self):
  from test_report_standard import fixture
  dep={'installed':'3.30910.0','resolution':{'upstream':'0.3.9.10'},'advisories':{'data':[advisory('>= 0.4.0, <= 0.4.9.1')]}}
  dep['matches']=engine.match_repository('nanopb',dep)
  model=engine.standard_platform(fixture(),[],[],{'nanopb':dep},[])
  excluded=next(x for x in model['blocks'] if x['key']=='excludedAdvisories')
  self.assertEqual(len(excluded['rows']),1);self.assertEqual(model['summary']['advisories'],0)
class AdditionalRangeTests(unittest.TestCase):
 def test_explicit_text_intervals_are_evaluated(self):
  self.assertFalse(engine.version_in_range('0.3.9.10','0.3.2 to 0.3.9.7, 0.4.0 to 0.4.4'))
  self.assertTrue(engine.version_in_range('0.4.4','0.3.2 to 0.3.9.7, 0.4.0 to 0.4.4'))
 def test_multiple_upper_bounds_are_ambiguous(self):
  self.assertIsNone(engine.version_in_range('0.3.9.5','<0.4.2, <0.3.9.6, <0.2.9.5'))
 def test_explicit_patch_in_same_branch_excludes_old_advisory(self):
  a=advisory('<0.4.1');a['vulnerabilities'][0]['patched_versions']='0.4.1, 0.3.9.5, 0.2.9.4'
  dep={'installed':'3.30910.0','resolution':{'upstream':'0.3.9.10'},'advisories':{'data':[a]}}
  self.assertEqual(engine.match_repository('nanopb',dep)[0]['state'],'excluded')
 def test_explicit_library_description_narrows_overbroad_metadata(self):
  a=advisory();a['description']='Affects versions nanopb-0.4.0 to nanopb-0.4.9.1.'
  dep={'installed':'3.30910.0','resolution':{'upstream':'0.3.9.10'},'advisories':{'data':[a]}}
  result=engine.match_repository('nanopb',dep)[0]
  self.assertEqual(result['state'],'excluded');self.assertIn('metadati',result['limits'])
  a['description']='Example versions nanopb-0.4.0 to nanopb-0.4.9.1.'
  self.assertEqual(engine.match_repository('nanopb',dep)[0]['state'],'affected')
 def test_nvd_exact_identity_and_boundary(self):
  cve={'id':'CVE-test','configurations':[{'nodes':[{'operator':'OR','cpeMatch':[{'vulnerable':True,'criteria':'cpe:2.3:a:webmproject:libwebp:*:*:*:*:*:*:*:*','versionEndExcluding':'1.3.2'},{'vulnerable':True,'criteria':'cpe:2.3:a:google:chrome:*:*:*:*:*:*:*:*','versionEndExcluding':'999.0.0'}]}]}],'weaknesses':[{'description':[{'value':'CWE-787'}]}]}
  response={'status':200,'data':{'totalResults':1,'vulnerabilities':[{'cve':cve}]}}
  with patch.object(engine,'request',return_value=response):
   result=engine.nvd_security('libwebp',{'installed':'1.6.0','resolution':{'upstream':'1.6.0'}},{})
  self.assertEqual(result['matches'][0]['state'],'excluded')
  self.assertEqual(result['matches'][0]['range'],'< 1.3.2')
  self.assertEqual(result['matches'][0]['cwes'],['CWE-787'])
class ArchiveInventoryTests(unittest.TestCase):
 def test_ipa_size_hash_and_nonpayload_symbols_are_separate(self):
  import tempfile,zipfile,hashlib
  from test_report_standard import fixture
  with tempfile.TemporaryDirectory() as temporary:
   ipa=pathlib.Path(temporary)/'Test.ipa'
   with zipfile.ZipFile(ipa,'w') as z:
    z.writestr('Payload/Test.app/Test',b'abc');z.writestr('Symbols/test.symbols',b'12345')
   inventory=engine.archive_inventory(ipa)
   self.assertEqual(inventory['package_bytes'],ipa.stat().st_size)
   self.assertEqual(inventory['input_sha256'],hashlib.sha256(ipa.read_bytes()).hexdigest())
   self.assertEqual([(x['group'],x['bytes']) for x in inventory['archive_contents']],[('Payload',3),('Symbols',5)])
   data=fixture();data.update(inventory)
   model=engine.standard_platform(data,[],[],{},[])
   self.assertEqual(model['summary']['packageBytes'],ipa.stat().st_size)
   self.assertEqual(model['summary']['contentBytes'],400)
   self.assertEqual(len(next(b for b in model['blocks'] if b['key']=='archiveContents')['rows']),2)
if __name__=='__main__':unittest.main()
