// Embedded Python standard-library collector. Keep package-specific assertions out of this engine.
import Foundation

enum AuditCollector {
    static let source = #"""
from pathlib import Path
from collections import defaultdict
import base64, hashlib, json, plistlib, zipfile, subprocess, re, concurrent.futures, xml.etree.ElementTree as ET, struct, os, sys, tempfile, shutil, datetime, urllib.request, urllib.error, urllib.parse

OUT=None
GITHUB_AUTH=None
SDK=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or str(Path.home()/'Library/Android/sdk'))
build_tools=sorted((SDK/'build-tools').glob('*'),key=lambda p:tuple(int(x) for x in re.findall(r'\d+',p.name)))
BUILD_TOOLS=build_tools[-1] if build_tools else SDK/'build-tools/missing'
ANDROID='{http://schemas.android.com/apk/res/android}'
def run(args):
 try: p=subprocess.run([str(x) for x in args],capture_output=True,timeout=180)
 except (OSError,subprocess.TimeoutExpired) as e:return {'exit':127,'stdout':'','stderr':str(e)}
 return {'exit':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')}
def digest(data): return hashlib.sha256(data).hexdigest()
def scan(data,path):
 # Only record indicators, never credential values or full endpoint paths.
 texts=re.findall(rb'[\x20-\x7e]{8,}',data)
 urls=[]; secrets=[]; flags=[]; versions=[]
 patterns={'private-key':rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----','AWS-access-key':rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b','GitHub-token':rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b','Stripe-secret':rb'\bsk_live_[A-Za-z0-9]{20,}\b','JWT-candidate':rb'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'}
 for label,pat in patterns.items():
  for m in re.finditer(pat,data):
   indicator={'type':label,'path':path,'offset':m.start(),'fingerprint':digest(m.group())[:16]}
   if label=='JWT-candidate':
    try:
     part=m.group().split(b'.')[1];payload=json.loads(base64.urlsafe_b64decode(part+b'='*(-len(part)%4)))
     expiry=payload.get('exp')
     if isinstance(expiry,(int,float)):
      indicator['expiry_utc']=datetime.datetime.fromtimestamp(expiry,datetime.timezone.utc).isoformat()
      indicator['expired']=expiry<datetime.datetime.now(datetime.timezone.utc).timestamp()
    except (ValueError,TypeError,OverflowError):pass
   secrets.append(indicator)
 for text in texts:
  for m in re.finditer(rb'https?://([A-Za-z0-9.-]+)(?::[0-9]+)?',text):
   if len(m.group(1))>3: urls.append(m.group(0).decode())
  for term in [b'badCertificateCallback',b'onReceivedSslError',b'X509TrustManager',b'HostnameVerifier',b'SetJavaScriptEnabled',b'setJavaScriptEnabled',b'addJavascriptInterface',b'setAllowFileAccess',b'setAllowUniversalAccessFromFileURLs',b'SSL_VERIFY_NONE',b'http_proxy',b'BEGIN CERTIFICATE']:
   if term in text: flags.append(term.decode())
  if re.search(rb'(?:Flutter [0-9]|Dart VM version|PDFium|pdfium version|OpenSSL [0-9]|BoringSSL|libpng version|LIBJPEG|SQLite [0-9])',text):
   versions.append(text.decode()[:220])
 return {'urls':sorted(set(urls)),'secret_candidates':secrets,'code_indicators':sorted(set(flags)),'version_strings':sorted(set(versions))[:100],'personal_data_fields':json_personal_fields(data) if path.endswith('.json') else []}
def json_personal_fields(data):
 if len(data)>2*1048576:return []
 try:value=json.loads(data)
 except (ValueError,UnicodeDecodeError):return []
 fields=[]
 def visit(node,path='',depth=0):
  if depth>20 or len(fields)>=100:return
  if isinstance(node,dict):
   for key,value in node.items():
    field=path+'.'+key if path else key
    if key.lower().replace('_','') in ('email','firstname','lastname','fullname','phonenumber','dateofbirth') and value not in (None,'',[],{}):fields.append(field)
    visit(value,field,depth+1)
  elif isinstance(node,list):
   for child in node[:30]:visit(child,path+'[]',depth+1)
 visit(value)
 return sorted(set(fields))

def category(p):
 if p.startswith('lib/'): return 'native'
 if p.endswith('.dex'): return 'dex'
 if 'flutter_assets/' in p: return 'flutter_assets'
 if p.startswith('Frameworks/'): return 'frameworks'
 if p.startswith('res/'): return 'android_resources'
 return 'other'
def elf(data):
 if data[:4]!=b'\x7fELF': return None
 is64=data[4]==2; e='<' if data[5]==1 else '>'
 fmt=e+('HHIQQQIHHHHHH' if is64 else 'HHIIIIIHHHHHH')
 h=struct.unpack_from(fmt,data,16); phoff=h[4]; phentsize=h[8]; phnum=h[9]
 seg=[]; dynamic=[]
 for i in range(phnum):
  vals=struct.unpack_from(e+('IIQQQQQQ' if is64 else 'IIIIIIII'),data,phoff+i*phentsize)
  if is64: typ,flags,off,vaddr,paddr,fs,ms,align=vals
  else: typ,off,vaddr,paddr,fs,ms,flags,align=vals
  seg.append({'type':typ,'flags':flags,'align':align})
  if typ==2:
   for j in range(off,off+fs,16 if is64 else 8):
    tag,val=struct.unpack_from(e+('qQ' if is64 else 'iI'),data,j)
    dynamic.append((tag,val))
 stack=[x for x in seg if x['type']==0x6474e551]
 return {'bits':64 if is64 else 32,'nx_stack':all(not x['flags']&1 for x in stack) if stack else None,'relro':any(x['type']==0x6474e552 for x in seg),'bind_now':any(t==24 or t==30 and v&8 or t==0x6ffffffb and v&1 for t,v in dynamic),'load_alignments':[x['align'] for x in seg if x['type']==1],'stack_canary_import':b'__stack_chk_fail' in data}
def dex_grant_classes(data):
 # Candidate discovery only; findings require confirmation in tool-decoded instructions.
 if not data.startswith(b'dex\n'):return []
 def u32(offset):return struct.unpack_from('<I',data,offset)[0]
 def uleb(offset):
  value=0
  for shift in range(0,35,7):
   byte=data[offset];offset+=1;value|=(byte&127)<<shift
   if byte<128:return value,offset
  raise ValueError('Malformed ULEB128')
 count,offset=u32(56),u32(60);strings=[]
 for i in range(count):
  start=u32(offset+i*4);_,start=uleb(start);end=data.index(b'\0',start);strings.append(data[start:end].decode(errors='replace'))
 types=[strings[u32(u32(68)+i*4)] for i in range(u32(64))]
 targets={i for i in range(u32(88)) if strings[u32(u32(92)+i*8+4)]=='grantUriPermission'}
 if not targets:return []
 classes=[]
 for i in range(u32(96)):
  offset=u32(100)+i*32;name=types[u32(offset)];cursor=u32(offset+24)
  if not cursor:continue
  counts=[]
  for _ in range(4):n,cursor=uleb(cursor);counts.append(n)
  for _ in range(counts[0]+counts[1]):_,cursor=uleb(cursor);_,cursor=uleb(cursor)
  for _ in range(counts[2]+counts[3]):
   _,cursor=uleb(cursor);_,cursor=uleb(cursor);code,cursor=uleb(cursor)
   if not code:continue
   size=u32(code+12);units=struct.unpack_from('<'+'H'*size,data,code+16)
   if any((unit&255) in (0x6e,0x6f,0x70,0x71,0x72,0x74,0x75,0x76,0x77,0x78) and units[j+1] in targets for j,unit in enumerate(units[:-2])):
    classes.append(name[1:-1].replace('/','.'));break
 return sorted(set(classes))

def smali_grants(code):
 results=[]
 for method in re.findall(r'\.method\b.*?\.end method',code,re.S):
  registers={};hits=[]
  for line in method.splitlines():
   line=line.strip().split(' #',1)[0]
   if not line or line.startswith('.') :continue
   if line.startswith(':') or line.startswith(('goto','if-','packed-switch','sparse-switch','return','throw')):registers.clear();continue
   constant=re.fullmatch(r'const(?:/4|/16|/high16)?\s+([vp]\d+),\s*(-?0x[0-9a-f]+|-?\d+)',line,re.I)
   if constant:
    value=int(constant[2],0);registers[constant[1]]=value<<16 if '/high16' in line else value;continue
   move=re.fullmatch(r'move(?:/from16|/16)?\s+([vp]\d+),\s*([vp]\d+)',line)
   if move:
    if move[2] in registers:registers[move[1]]=registers[move[2]]
    else:registers.pop(move[1],None)
    continue
   call=re.search(r'invoke-(?:virtual|interface)(?:/range)?\s+\{([^}]+)\},\s*L[^;]+;->grantUriPermission\(Ljava/lang/String;Landroid/net/Uri;I\)V',line)
   if call:
    args=[x.strip() for x in call[1].split(',')]
    if '..' in call[1]:
     m=re.fullmatch(r'([vp])(\d+)\s*\.\.\s*([vp])(\d+)',call[1])
     args=[m[1]+str(i) for i in range(int(m[2]),int(m[4])+1)] if m and m[1]==m[3] else []
    flags=registers.get(args[-1]) if args else None
    if flags is not None and flags&3==3:hits.append({'flags':flags,'instruction':line})
   if line.startswith('invoke-'):continue
   # Invalidate a written register when its value is not a proven literal/move.
   destination=re.match(r'\S+\s+([vp]\d+)(?:,|$)',line)
   if destination:registers.pop(destination[1],None)
  if hits:results.append({'method':method.splitlines()[0], 'grants':hits,'resolver_query_present':'->queryIntentActivities(' in method})
 return results

def collect_grants(apk,label):
 candidates=[];diagnostics=[];results=[]
 with zipfile.ZipFile(apk) as archive:
  for name in archive.namelist():
   if not name.endswith('.dex'):continue
   try:candidates.extend(dex_grant_classes(archive.read(name)))
   except (ValueError,IndexError,struct.error) as e:diagnostics.append({'dex':name,'error':str(e)})
 for name in sorted(set(candidates))[:40]:
  decoded=run([SDK/'cmdline-tools/latest/bin/apkanalyzer','dex','code','--class',name,apk]);matches=smali_grants(decoded['stdout']) if decoded['exit']==0 else []
  diagnostics.append({'class':name,'exit':decoded['exit'],'stderr':decoded['stderr']})
  if matches:
   filename=label+'-grant-'+re.sub(r'[^A-Za-z0-9_-]','_',name)+'.smali';(OUT/filename).write_text(decoded['stdout'])
   results.extend({'class':name,'evidence_file':filename,**m} for m in matches)
 return {'matches':results,'diagnostics':diagnostics,'candidate_classes':len(set(candidates)),'truncated':len(set(candidates))>40}


def collect(kind,p,label):
 records=[]; scans=[]; versions=[]; native=[]; fw=[]
 result={'label':label,'platform':kind,'input':str(p),'audit_date':datetime.date.today().isoformat()}
 if kind=='Android':
  result['input_sha256']=digest(p.read_bytes()); result['package_bytes']=p.stat().st_size
  manifest=run([SDK/'cmdline-tools/latest/bin/apkanalyzer','manifest','print',p]); (OUT/(label+'-manifest.xml')).write_text(manifest['stdout'])
  if manifest['exit']: raise RuntimeError('Android manifest unavailable; install Android SDK cmdline-tools and set ANDROID_SDK_ROOT. '+manifest['stderr'])
  tree=ET.fromstring(manifest['stdout']);app=tree.find('application')
  result['manifest']={'package':tree.get('package'),'version':tree.get(ANDROID+'versionName'),'build':tree.get(ANDROID+'versionCode'),'sdk':{k.split('}')[1]:v for k,v in tree.find('uses-sdk').attrib.items()},'application':{k.split('}')[-1]:v for k,v in app.attrib.items()},'permissions':[{k.split('}')[-1]:v for k,v in x.attrib.items()} for x in tree.findall('uses-permission')],'components':[]}
  for c in app:
   if c.tag in ('activity','activity-alias','service','provider','receiver'):
    result['manifest']['components'].append({'type':c.tag,**{k.split('}')[-1]:v for k,v in c.attrib.items()},'intent_filters':[ET.tostring(x,encoding='unicode') for x in c.findall('intent-filter')]})
  result['signing']=run([BUILD_TOOLS/'apksigner','verify','--verbose','--print-certs',p])
  result['zip_alignment']=run([BUILD_TOOLS/'zipalign','-c','-P','16','-v','4',p])
  result['uri_grants']=collect_grants(p,label)
  with zipfile.ZipFile(p) as z:
   for entry in z.infolist():
    if entry.is_dir(): continue
    data=z.read(entry); path=entry.filename
    records.append({'path':path,'bytes':len(data),'compressed_bytes':entry.compress_size,'sha256':digest(data),'category':category(path)})
    if path.endswith(('.properties','.version')) and len(data)<10000: versions.append({'path':path,'content':data.decode(errors='replace').strip()})
    if path.endswith('.so'):
     try:native.append({'path':path,**(elf(data) or {})})
     except (struct.error,IndexError):native.append({'path':path,'error':'Malformed ELF'})
    if len(data)>0 and not path.endswith(('.png','.jpg','.jpeg','.webp','.gif','.ttf','.otf')): scans.append({'path':path,**scan(data,path)})
    if path.startswith('res/') and path.endswith('.xml'):
     x=run([BUILD_TOOLS/'aapt2','dump','xmltree',p,'--file',path])
     if any(t in x['stdout'] for t in ('root-path','external-path','cache-path','trust-anchors','base-config','data-extraction-rules')):
      (OUT/(label+'-'+path.replace('/','_')+'.txt')).write_text(x['stdout'])
  result['versions']=versions;result['native']=native
 else:
  info=plistlib.loads((p/'Info.plist').read_bytes()); result['info']=info
  exe=p/info['CFBundleExecutable'];result['main_executable_exists']=exe.exists()
  result['signing']=run(['codesign','-d','--entitlements',':-',p]);result['signature_verification']=run(['codesign','--verify','--deep','--strict',p])
  main=run(['otool','-hv',exe]);libs=run(['otool','-L',exe]); cmds=run(['otool','-l',exe]);symbols=run(['nm','-u',exe])
  (OUT/(label+'-main-otool.txt')).write_text(main['stdout']+libs['stdout']+cmds['stdout'])
  result['main_macho']={'header':main['stdout'],'libraries':libs['stdout'],'has_pie':'PIE' in main['stdout'],'stack_canary_import':'___stack_chk_fail' in symbols['stdout'],'cryptid':re.findall(r'cryptid\s+(\d+)',cmds['stdout']),'rpaths':re.findall(r'path (\S+) \(offset',cmds['stdout'])}
  for f in sorted(p.rglob('*')):
   if not f.is_file() or f.is_symlink(): continue
   data=f.read_bytes();path=str(f.relative_to(p))
   records.append({'path':path,'bytes':len(data),'sha256':digest(data),'category':category(path)})
   if len(data)>0 and not path.endswith(('.png','.jpg','.jpeg','.webp','.gif','.ttf','.otf')): scans.append({'path':path,**scan(data,path)})
   if f.name=='PrivacyInfo.xcprivacy':
    try: result.setdefault('privacy_manifests',[]).append({'path':path,'data':plistlib.loads(data)})
    except Exception: pass
  for d in sorted(p.rglob('*.framework')):
   pi=d/'Info.plist';x=plistlib.loads(pi.read_bytes()) if pi.exists() else {}
   fp=d/x.get('CFBundleExecutable',d.stem)
   header=run(['otool','-hv',fp]); lib=run(['otool','-L',fp]);sym=run(['nm','-u',fp])
   fw.append({'name':d.name,'path':str(d.relative_to(p)),'version':x.get('CFBundleShortVersionString'),'build':x.get('CFBundleVersion'),'identifier':x.get('CFBundleIdentifier'),'bytes':sum(y.stat().st_size for y in d.rglob('*') if y.is_file()),'binary_bytes':fp.stat().st_size if fp.exists() else None,'header':header['stdout'],'libraries':lib['stdout'],'canary_import':'___stack_chk_fail' in sym['stdout']})
  result['frameworks']=fw
 groups=defaultdict(list); sizes=defaultdict(int)
 for r in records:
  groups[(r['sha256'],r['bytes'])].append(r);sizes[r['category']]+=r['bytes']
 duplicates=[{'sha256':h,'bytes_each':size,'copies':len(rs),'redundant_bytes':size*(len(rs)-1),'paths':[r['path'] for r in rs]} for (h,size),rs in groups.items() if size>0 and len(rs)>1]
 duplicates.sort(key=lambda x:x['redundant_bytes'],reverse=True)
 result.update({'uncompressed_bytes':sum(r['bytes'] for r in records),'file_count':len(records),'categories':dict(sizes),'largest_files':sorted(records,key=lambda x:x['bytes'],reverse=True)[:40],'duplicates':duplicates,'duplicate_redundant_bytes':sum(x['redundant_bytes'] for x in duplicates),'scan':scans})
 (OUT/(label+'-files.json')).write_text(json.dumps(records,indent=2))
 (OUT/(label+'-audit.json')).write_text(json.dumps(result,indent=2,default=str))
 print(label,'DONE',result['uncompressed_bytes'],'duplicates',result['duplicate_redundant_bytes'],flush=True)
 return result

def request(url,payload=None):
 global GITHUB_AUTH
 try:
  body=json.dumps(payload).encode() if payload is not None else None
  headers={'User-Agent':'FRTMTools-static-audit','Accept':'application/json','Content-Type':'application/json'}
  if urllib.parse.urlparse(url).netloc=='api.github.com':
   if GITHUB_AUTH is None:
    GITHUB_AUTH=os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN') or ''
    if not GITHUB_AUTH and shutil.which('gh'):
     auth=run(['gh','auth','token']);GITHUB_AUTH=auth['stdout'].strip() if auth['exit']==0 else ''
   if GITHUB_AUTH:headers['Authorization']='Bearer '+GITHUB_AUTH
  req=urllib.request.Request(url,data=body,headers=headers)
  with urllib.request.urlopen(req,timeout=30) as response:return {'status':response.status,'data':json.load(response),'url':url,'retrieved_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'next':response.headers.get('Link','')}
 except Exception as e:return {'status':'unavailable','error':str(e),'url':url}

def maven_packages(versions):
 packages=[]
 for v in versions:
  name=Path(v['path']).name;content=v['content'];artifact=None;version=None
  if name.endswith('.version') and re.fullmatch(r'\d+(?:\.\d+)+(?:[-.][A-Za-z0-9]+)*',content):
   n=name[:-8];version=content
   if n.startswith('androidx.') and '_' in n:group,a=n.split('_',1);artifact=group+':'+a
   elif n=='com.google.dagger_dagger':artifact='com.google.dagger:dagger'
   elif n.startswith('kotlinx_coroutines_'):artifact='org.jetbrains.kotlinx:kotlinx-coroutines-'+n.removeprefix('kotlinx_coroutines_').replace('_','-')
  elif name.endswith('.properties'):
   m=re.search(r'^version=(\S+)',content,re.M)
   if m:
    a=name[:-11];version=m.group(1)
    if a.startswith('firebase-'):artifact='com.google.firebase:'+a
    elif a.startswith('play-services-'):artifact='com.google.android.gms:'+a
    elif a in ('face-detection','text-recognition','common','vision-common','vision-interfaces','text-recognition-bundled-common'):artifact='com.google.mlkit:'+a
    elif a in ('review','review-ktx','integrity'):artifact='com.google.android.play:'+a
    elif a=='recaptcha':artifact='com.google.android.recaptcha:recaptcha'
    elif a=='googleid':artifact='com.google.android.libraries.identity.googleid:googleid'
  if artifact:packages.append({'package':{'name':artifact,'ecosystem':'Maven'},'version':version,'evidence':v['path']})
 return packages

REPOS={'Firebase':'firebase/firebase-ios-sdk','Facebook':'facebook/facebook-ios-sdk','SDWebImage':'SDWebImage/SDWebImage','SDWebImageWebPCoder':'SDWebImage/SDWebImageWebPCoder','AppAuth':'openid/AppAuth-iOS','GoogleSignIn':'google/GoogleSignIn-iOS','IOSSecuritySuite':'securing/IOSSecuritySuite','GTMSessionFetcher':'google/gtm-session-fetcher','nanopb':'nanopb/nanopb','libwebp':'webmproject/libwebp','DKImagePickerController':'zhangao0086/DKImagePickerController','DKPhotoGallery':'zhangao0086/DKPhotoGallery','SwiftyGif':'kirualex/SwiftyGif','GTMAppAuth':'google/GTMAppAuth','GoogleUtilities':'google/GoogleUtilities','AppCheckCore':'google/app-check','GoogleDataTransport':'google/GoogleDataTransport','GoogleToolboxForMac':'google/google-toolbox-for-mac','FBLPromises':'google/promises','Promises':'google/promises','SSZipArchive':'ZipArchive/ZipArchive','Alamofire':'Alamofire/Alamofire'}
# Stable numeric ranges only. Unsupported syntax and prereleases remain unknown.
def numeric_version(value):
 if not isinstance(value,str) or not re.fullmatch(r'v?\d+(?:\.\d+){1,4}',value):return None
 parts=tuple(int(x) for x in value.lstrip('v').split('.'))
 return parts+(0,)*(5-len(parts))
def version_in_range(version,expression):
 value=numeric_version(version)
 if value is None or not expression:return None
 intervals=re.fullmatch(r'\s*(\d+(?:\.\d+)+\s+to\s+\d+(?:\.\d+)+)(?:\s*,\s*\d+(?:\.\d+)+\s+to\s+\d+(?:\.\d+)+)*\s*',expression)
 if intervals:expression=' || '.join('>= '+low+', <= '+high for low,high in re.findall(r'(\d+(?:\.\d+)+)\s+to\s+(\d+(?:\.\d+)+)',expression))
 outcomes=[]
 for alternative in expression.split('||'):
  clauses=[x.strip() for x in alternative.split(',')];matches=[]
  for clause in clauses:
   m=re.fullmatch(r'(<=|>=|<|>|=)?\s*(v?\d+(?:\.\d+){1,4})',clause)
   if not m:matches.append(None);continue
   boundary=numeric_version(m[2]);op=m[1] or '='
   matches.append({'<':value<boundary,'<=':value<=boundary,'>':value>boundary,'>=':value>=boundary,'=':value==boundary}[op])
  if len(clauses)>1 and all(re.match(r'^<',x) for x in clauses):matches=[None]
  outcomes.append(False if False in matches else None if None in matches else True)
 return True if True in outcomes else None if None in outcomes else False

def cached_request(cache,url,payload=None,offline=False):
 key=url+' '+json.dumps(payload,sort_keys=True)
 if key not in cache:cache[key]={'status':'offline','url':url} if offline else request(url,payload)
 return cache[key]
def repository_advisories(repo,cache,offline=False):
 url='https://api.github.com/repos/'+repo+'/security-advisories?per_page=100';items=[];pages=[]
 for _ in range(10):
  page=cached_request(cache,url,offline=offline);pages.append(page)
  if page.get('status')!=200 or not isinstance(page.get('data'),list):return {'status':page.get('status'),'data':items,'pages':pages,'complete':False}
  items.extend(page['data']);m=re.search(r'<([^>]+)>; rel="next"',page.get('next',''))
  if not m:return {'status':200,'data':items,'pages':pages,'complete':True}
  url=m[1]
  if not url.startswith('https://api.github.com/'):break
 return {'status':'partial','data':items,'pages':pages,'complete':False}

def resolve_pod(name,version,cache,offline=False):
 result={'pod':name,'installed':version,'upstream':None,'evidence':'Framework Info.plist'}
 if numeric_version(version) is None or version in ('0.0.1','1.0','1.0.0'):return result
 # CocoaPods Specs stores pod names under the first three MD5 digits.
 shard='/'.join(hashlib.md5(name.encode()).hexdigest()[:3])
 url='https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/'+shard+'/'+urllib.parse.quote(name,safe='')+'/'+urllib.parse.quote(version,safe='')+'/'+urllib.parse.quote(name,safe='')+'.podspec.json'
 spec=cached_request(cache,url,offline=offline);result['podspec']=spec
 data=spec.get('data',{})
 if spec.get('status')!=200 or data.get('name')!=name or data.get('version')!=version:return result
 source=data.get('source',{});tag=source.get('tag');repo=REPOS.get(name)
 # Use a tag only when the official spec points at the identified upstream.
 if not repo or str(source.get('git','')).removesuffix('.git').rstrip('/')!='https://github.com/'+repo:return result
 if not isinstance(tag,str):return result
 tag=tag.replace('${version}',version)
 upstream=tag.lstrip('v')
 if numeric_version(upstream) is not None:result.update({'upstream':upstream,'evidence':url+'; source.tag='+tag})
 return result

def match_repository(component,dependency):
 records=[];resolution=dependency.get('resolution',{});installed=dependency.get('installed');version=resolution.get('upstream')
 # A declared version needs an official spec/tag mapping before range comparison.
 for advisory in dependency.get('advisories',{}).get('data',[]):
  if not isinstance(advisory,dict) or advisory.get('withdrawn_at') or not advisory.get('ghsa_id'):continue
  vulnerabilities=advisory.get('vulnerabilities',[]);eligible=[]
  for vulnerability in vulnerabilities:
   package=vulnerability.get('package',{});package_name=package.get('name','')
   if package_name.lower() in {component.lower(),REPOS.get(component,'').lower()}:
    eligible.append(vulnerability)
  outcomes=[version_in_range(version,x.get('vulnerable_version_range')) for x in eligible]
  state='affected' if True in outcomes else 'excluded' if outcomes and all(x is False for x in outcomes) else 'unknown'
  chosen=[x for x,o in zip(eligible,outcomes) if o is True] if state=='affected' else eligible
  ranges=' || '.join(x.get('vulnerable_version_range') or 'Non specificato' for x in chosen)
  patches=[]
  for x in chosen:
   patch=x.get('patched_versions') or x.get('first_patched_version')
   if isinstance(patch,dict):patch=patch.get('identifier')
   if patch:patches.append(patch)
  # A narrowly defined, explicit affected-version sentence can narrow broad metadata.
  described=re.findall(r'Affects versions '+re.escape(component)+r'-(\d+(?:\.\d+)+) to '+re.escape(component)+r'-(\d+(?:\.\d+)+)',advisory.get('description',''),re.I)
  description_excludes=bool(described) and version is not None and all(version_in_range(version,'>= '+low+', <= '+high) is False for low,high in described)
  if described:ranges+='; descrizione: '+' || '.join('>= '+low+', <= '+high for low,high in described)
  if description_excludes:state='excluded'
  version_number=numeric_version(version)
  branch_fixes=[numeric_version(x.strip()) for patch in patches for x in patch.split(',') if numeric_version(x.strip()) is not None]
  branch_fixed=version_number is not None and any(version_number[:2]==fix[:2] and version_number>=fix for fix in branch_fixes)
  if branch_fixed:state='excluded'
  records.append({'component':component,'installed':installed,'matchedVersion':version,'id':advisory['ghsa_id'],'cve':advisory.get('cve_id'),'severity':advisory.get('severity'),'cwes':[x['cwe_id'] for x in advisory.get('cwes',[]) if x.get('cwe_id')],'range':ranges or None,'patch':'; '.join(dict.fromkeys(patches)) or None,'state':state,'summary':advisory.get('summary'),'url':advisory.get('html_url') or 'https://github.com/advisories/'+advisory['ghsa_id'],'cvss':advisory.get('cvss',{}),'evidence':resolution.get('evidence'),'limits':'Corrispondenza numerica; ramo, opzioni di compilazione e raggiungibilità non verificati' if state=='affected' else 'Escluso dall’intervallo esplicito nella descrizione; metadati del range più ampi' if description_excludes else 'Correzione dichiarata nel ramo della versione presente' if branch_fixed else 'Versione fuori dagli intervalli dichiarati' if state=='excluded' else 'Identità del pacchetto, versione upstream o sintassi del range non risolte'})
 return records

def osv_security(packages,cache,offline=False):
 queries=[{k:v for k,v in x.items() if k in ('package','version')} for x in packages]
 result={'status':'offline' if offline else 'empty','packages':packages,'matches':[],'details':{}}
 if not packages or offline:return result
 result.update(cached_request(cache,'https://api.osv.dev/v1/querybatch',{'queries':queries}))
 if result.get('status')!=200:return result
 for package,batch in zip(packages,result.get('data',{}).get('results',[])):
  for hit in batch.get('vulns',[]):
   identifier=hit['id'];detail=cached_request(cache,'https://api.osv.dev/v1/vulns/'+urllib.parse.quote(identifier,safe=''));result['details'][identifier]=detail
   advisory=detail.get('data',{})
   if advisory.get('withdrawn'):continue
   relevant=[x for x in advisory.get('affected',[]) if x.get('package',{}).get('name')==package['package']['name'] and x.get('package',{}).get('ecosystem')==package['package']['ecosystem']]
   patches=sorted(set(e['fixed'] for x in relevant for r in x.get('ranges',[]) for e in r.get('events',[]) if 'fixed' in e))
   cwes=advisory.get('database_specific',{}).get('cwe_ids',[]);sev=advisory.get('database_specific',{}).get('severity')
   aliases=advisory.get('aliases',[]);ghsa=next((x for x in [identifier]+aliases if x.startswith('GHSA-')),None)
   if ghsa:
    github=cached_request(cache,'https://api.github.com/advisories/'+ghsa);result['details'][ghsa]=github;data=github.get('data',{})
    cwes=cwes or [x['cwe_id'] for x in data.get('cwes',[]) if x.get('cwe_id')];sev=sev or data.get('severity')
   result['matches'].append({'component':package['package']['name'],'installed':package['version'],'matchedVersion':package['version'],'id':ghsa or identifier,'aliases':aliases,'cve':next((x for x in aliases if x.startswith('CVE-')),None),'severity':sev,'cwes':cwes,'range':json.dumps([r for x in relevant for r in x.get('ranges',[])],ensure_ascii=False) or None,'patch':'; '.join(patches) or None,'state':'affected','summary':advisory.get('summary'),'url':'https://github.com/advisories/'+ghsa if ghsa else 'https://osv.dev/vulnerability/'+identifier,'evidence':package.get('evidence'),'limits':'Versione corrispondente nella query OSV; prerequisiti e raggiungibilità non verificati'})
 return result

# Explicit upstream identities, never keyword matches to similarly named products.
NVD_CPE={'libwebp':'cpe:2.3:a:webmproject:libwebp','SSZipArchive':'cpe:2.3:a:ziparchive_project:ziparchive'}
def nvd_security(component,dependency,cache,offline=False):
 identity=NVD_CPE.get(component)
 result={'matches':[],'responses':[]}
 if not identity:return result
 start=0;total=1
 while start<total:
  url='https://services.nvd.nist.gov/rest/json/cves/2.0?'+urllib.parse.urlencode({'virtualMatchString':identity,'resultsPerPage':2000,'startIndex':start})
  response=cached_request(cache,url,offline=offline);result['responses'].append(response)
  if response.get('status')!=200:return result
  data=response.get('data',{});total=data.get('totalResults',0);items=data.get('vulnerabilities',[])
  for item in items:
   cve=item.get('cve',{})
   if cve.get('vulnStatus')=='Rejected':continue
   matches=[]
   for configuration in cve.get('configurations',[]):
    for node in configuration.get('nodes',[]):
     for candidate in node.get('cpeMatch',[]):
      if candidate.get('vulnerable') and candidate.get('criteria','').startswith(identity+':'):
       clauses=[]
       for field,op in [('versionStartIncluding','>='),('versionStartExcluding','>'),('versionEndIncluding','<='),('versionEndExcluding','<')]:
        if candidate.get(field):clauses.append(op+' '+candidate[field])
       explicit=candidate['criteria'].split(':')[5]
       if explicit not in ('*','-'):clauses.append('= '+explicit)
       range=', '.join(clauses)
       state=version_in_range(dependency.get('resolution',{}).get('upstream'),range)
       if node.get('negate') or configuration.get('negate') or node.get('operator')=='AND' or configuration.get('operator')=='AND':state=None
       matches.append((state,range,candidate))
   if not matches:continue
   state='affected' if any(x[0] is True for x in matches) else 'excluded' if all(x[0] is False for x in matches) else 'unknown'
   metrics=cve.get('metrics',{});metric=next((values[0] for key in ('cvssMetricV40','cvssMetricV31','cvssMetricV30','cvssMetricV2') if (values:=metrics.get(key))),{})
   severity=metric.get('cvssData',{}).get('baseSeverity') or metric.get('baseSeverity')
   cwes=sorted(set(x['value'] for w in cve.get('weaknesses',[]) for x in w.get('description',[]) if x.get('value','').startswith('CWE-')))
   patches=sorted(set(x[2]['versionEndExcluding'] for x in matches if x[2].get('versionEndExcluding')))
   result['matches'].append({'component':component,'installed':dependency.get('installed'),'matchedVersion':dependency.get('resolution',{}).get('upstream'),'id':cve['id'],'cve':cve['id'],'severity':severity,'cwes':cwes,'range':' || '.join(x[1] for x in matches) or None,'patch':'; '.join(patches) or None,'state':state,'summary':next((x['value'] for x in cve.get('descriptions',[]) if x.get('lang')=='en'),None),'url':'https://nvd.nist.gov/vuln/detail/'+cve['id'],'evidence':dependency.get('resolution',{}).get('evidence'),'limits':'Versione fuori dagli intervalli CPE dichiarati' if state=='excluded' else 'Corrispondenza CPE/versione; prerequisiti e raggiungibilità non verificati' if state=='affected' else 'Versione o condizioni CPE non risolte'})
  if not items:break
  start+=len(items)
 return result

def dependency_audit(d,offline=False,cache=None):
 cache={} if cache is None else cache
 if d['platform']=='Android':
  packages=maven_packages(d.get('versions',[]));deps=osv_security(packages,cache,offline)
  deps['updates']=[] if offline else google_updates(packages)
  return deps
 deps={};packages=[]
 for name in sorted({family(x) for x in d.get('frameworks',[])}-{None}):
  frameworks=[x for x in d['frameworks'] if family(x)==name];installed=frameworks[0].get('build') if name=='Facebook' else frameworks[0].get('version')
  # A family containing inconsistent versions is never collapsed to one match.
  measured={x.get('build') if name=='Facebook' else x.get('version') for x in frameworks}
  resolution=resolve_pod(name,installed,cache,offline) if len(measured)==1 else {'installed':installed,'evidence':'Versioni discordanti nel gruppo','upstream':None}
  deps[name]={'installed':installed,'resolution':resolution,'latest':cached_request(cache,'https://api.github.com/repos/'+REPOS[name]+'/releases/latest',offline=offline),'advisories':repository_advisories(REPOS[name],cache,offline)}
  deps[name]['matches']=match_repository(name,deps[name])
  if name in NVD_CPE:
   deps[name]['nvd']=nvd_security(name,deps[name],cache,offline);deps[name]['matches'].extend(deps[name]['nvd']['matches'])
 # CocoaPods is not an OSV query ecosystem; use repository advisories and exact CPEs.
 return deps

def advisory_records(d,dependencies):
 candidates=list(dependencies.get('matches',[])) if d['platform']=='Android' else [record for dep in dependencies.values() for record in dep.get('matches',[])]
 merged={}
 for record in candidates:
  key=(record['component'],record.get('cve') or record['id'])
  if key not in merged or record['state']=='affected':merged[key]=record
 return list(merged.values())
def advisory_findings(d,dependencies):
 findings=[]
 for record in advisory_records(d,dependencies):
  if record['state']=='excluded':continue
  cwe=' / '.join(record.get('cwes',[])) or '—'
  priority={'critical':'Alta','high':'Alta','moderate':'Media','medium':'Media','low':'Bassa'}.get(str(record.get('severity')).lower(),'Da verificare') if record['state']=='affected' else 'Da verificare'
  evidence=record['component']+' '+str(record['installed'])+'; upstream '+str(record.get('matchedVersion') or 'non risolta')+'; range '+str(record.get('range') or 'non risolto')+'; '+str(record.get('evidence') or '')
  findings.append({'id':record['id'],'priority':priority,'cwe':cwe,'title':'Advisory candidato: '+record['component'],'evidence':evidence,'fix':'Verificare prerequisiti e compatibilità; correzione indicata: '+str(record.get('patch') or 'non dichiarata'),'status':record['limits'],'origin':'cli'})
 return findings

def google_updates(packages):
 selected={'androidx.appcompat:appcompat','androidx.webkit:webkit','androidx.biometric:biometric','com.google.firebase:firebase-auth','com.google.firebase:firebase-messaging','com.google.android.play:integrity','com.google.android.recaptcha:recaptcha','com.google.mlkit:face-detection'}
 def lookup(package):
  coordinate=package['package']['name'];group,artifact=coordinate.split(':',1)
  url='https://dl.google.com/dl/android/maven2/'+group.replace('.','/')+'/'+artifact+'/maven-metadata.xml'
  try:
   with urllib.request.urlopen(url,timeout=20) as response:tree=ET.fromstring(response.read())
   versions=[x.text for x in tree.findall('.//version') if x.text and re.fullmatch(r'\d+(?:\.\d+)+',x.text)]
   latest=max(versions,key=lambda x:tuple(int(v) for v in x.split('.'))) if versions else 'Non verificata'
   return {'coordinate':coordinate,'installed':package['version'],'latest_stable':latest,'status':'Verificato','update':latest!=package['version']}
  except Exception as e:return {'coordinate':coordinate,'installed':package['version'],'latest_stable':'Non verificata','status':'Non disponibile'}
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:return list(pool.map(lookup,[p for p in packages if p['package']['name'] in selected]))

def family(f):
 n=f['name'].removesuffix('.framework')
 if n.startswith('Firebase'):return 'Firebase'
 if n.startswith(('FBSDK','FBAEM')):return 'Facebook'
 return n if n in REPOS else None

def measure_strip(app):
 binaries=[app/plistlib.loads((app/'Info.plist').read_bytes())['CFBundleExecutable']]
 for fw in sorted(app.rglob('*.framework')):
  info=plistlib.loads((fw/'Info.plist').read_bytes()) if (fw/'Info.plist').exists() else {}
  binaries.append(fw/info.get('CFBundleExecutable',fw.stem))
 results=[]
 with tempfile.TemporaryDirectory(prefix='frtm-strip-') as temporary:
  for i,b in enumerate(binaries):
   if not b.is_file():continue
   dst=Path(temporary)/str(i);shutil.copy2(b,dst);result=run(['xcrun','strip','-S','-x',dst])
   results.append({'path':str(b.relative_to(app)),'before':b.stat().st_size,'saving':max(0,b.stat().st_size-dst.stat().st_size) if result['exit']==0 else None,'status':result['exit']})
 return results

def findings(d,files):
 f=[]
 def add(id,priority,cwe,title,evidence,fix,status='Confermato; sfruttabilità da verificare'):
  f.append({'id':id,'priority':priority,'cwe':cwe,'title':title,'evidence':evidence,'fix':fix,'status':status,'origin':'cli'})
 android=d['platform']=='Android'
 signature=d['signing'] if android else d['signature_verification']
 # Failed verification tools are diagnostics, not application findings.
 if android:
  app=d['manifest']['application']
  if app.get('debuggable')=='true':add('DEBUG','Alta','CWE-489','Debug Android abilitato','debuggable=true','Disabilitare nella build di distribuzione.')
  if app.get('usesCleartextTraffic')=='true':add('CLEARTEXT','Media','CWE-319','Traffico in chiaro consentito','usesCleartextTraffic=true','Limitare a HTTPS e alle sole eccezioni richieste.')
  for resource in OUT.glob(d['label']+'-res_*.txt'):
   text=resource.read_text()
   if 'root-path' in text:add('FILEPROVIDER','Alta','CWE-732','FileProvider con root-path',resource.name,'Limitare a una directory temporanea di export e grant in sola lettura.','Configurazione confermata; associazione provider e grant da verificare')
  bad=[x['path'] for x in d['native'] if x.get('bits')==64 and any(a<16384 for a in x.get('load_alignments',[]))]
  if bad:add('ELF16K','Alta','—','Librerie con PT_LOAD inferiore a 16 KB','; '.join(bad),'Aggiornare/ricompilare le dipendenze e testare su device da 16 KB.','Allineamento confermato; impatto su device da verificare')
  for grant in d.get('uri_grants',{}).get('matches',[]):
   add('URI-WRITE','Media','CWE-732','Concessione URI di lettura e scrittura',grant['class']+'; '+grant['method']+'; flags='+str(grant['grants'][0]['flags'])+'; '+grant['evidence_file'],'Limitare i grant ai permessi necessari e al destinatario scelto.','Argomento costante confermato nel bytecode; attivazione runtime non verificata')
  if re.search(r'Local Debug|Android Debug|OU=Development',d['signing']['stdout'],re.I):add('SIGNING','Media','—','Identità di firma di sviluppo','Certificato dichiarato debug/development','Verificare certificato e canale di distribuzione.','Identità del certificato; non implica debuggable=true')
 else:
  text=d['signing']['stdout']+d['signing']['stderr']
  if re.search(r'<key>get-task-allow</key>\s*<true\s*/>',text):add('DEBUG','Media PRE / Alta PROD','CWE-489','Entitlement di debug attivo','get-task-allow=true','Esportare con profilo di distribuzione e get-task-allow=false.')
  ats=d['info'].get('NSAppTransportSecurity',{})
  if ats.get('NSAllowsArbitraryLoads'):add('CLEARTEXT','Media','CWE-319','ATS consente arbitrary loads','NSAllowsArbitraryLoads=true','Ripristinare ATS e limitare eventuali eccezioni.')
 mock_paths=[entry['path'] for entry in files if 'mock' in Path(entry['path']).parts and entry['path'].endswith('.json')]
 if mock_paths:add('MOCK','Bassa','—','Fixture mock nel pacchetto','; '.join(mock_paths),'Escludere fixture non necessarie dalle build distribuite.','Presenza confermata; autenticità dei dati sconosciuta')
 for entry in files:
  if entry['path'].endswith('/pdfium.wasm'):add('WASM','Media','—','Renderer web nel pacchetto nativo',entry['path']+'; '+str(entry['bytes'])+' byte','Verificare flussi PDF/WebView prima di rimuovere l’asset.','Presenza confermata; inutilizzo non dimostrato')
 secrets=[x for scan in d['scan'] for x in scan['secret_candidates'] if x['type']=='JWT-candidate']
 for secret in secrets[:30]:add('JWT','Media','CWE-200 / CWE-312 condizionali','JWT leggibile nel pacchetto',secret['path']+'; fingerprint '+secret['fingerprint']+'; scadenza '+secret.get('expiry_utc','non identificata')+'; scaduto '+str(secret.get('expired','non verificato')),'Verificare sensibilità, scadenza e origine; rimuovere fixture con dati reali.','Indicatore; validità e uso runtime sconosciuti')
 for entry in d['scan']:
  for secret in entry.get('secret_candidates',[]):
   if secret['type']!='JWT-candidate':add('SECRET','Alta','CWE-798 condizionale','Indicatore di credenziale nel pacchetto',secret['type']+'; '+secret['path']+'; fingerprint '+secret['fingerprint'],'Verificare autenticità; rimuovere e ruotare se la credenziale è reale.','Pattern statico; validità e uso non verificati')
  if entry.get('personal_data_fields'):add('PII-FIELDS','Media','CWE-200 condizionale','Campi identificativi in JSON',entry['path']+'; campi: '+', '.join(entry['personal_data_fields']),'Verificare provenienza; usare fixture sintetiche ed escludere dati reali.','Struttura confermata; dati reali o sintetici non determinabili')
 return f

STYLE='body{font:14px/1.5 system-ui;margin:0;background:#f3f5f8;color:#192435}main{max-width:1250px;margin:auto;padding:28px}section{background:#fff;border:1px solid #dde3eb;border-radius:12px;padding:20px;margin:16px 0}a{color:#1556a4}.wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:9px;text-align:left;vertical-align:top;border-bottom:1px solid #dde3eb;overflow-wrap:anywhere;min-width:80px}th{background:#f3f5f8}summary{cursor:pointer;padding:12px;font-weight:600}nav{display:flex;gap:15px;flex-wrap:wrap}'
def h(x):return __import__('html').escape(str(x))
def render_table(headers,rows):
 return '<div class="wrap"><table><thead><tr>'+''.join('<th>'+h(x)+'</th>' for x in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+h(x)+'</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table></div>'
# Presentation contract; only artifact evidence enters this module.
import json,re,plistlib,collections,html
from pathlib import Path
SCHEMA_VERSION='1.2'
STANDARD_FIELDS=['summary','sizeBreakdown','categories','libraries','advisories','excludedAdvisories','assessment','duplicates','privacy','entitlements','hardening','buildQuality','connections','localization','deadCode','permissions','components','dynamicModules','maintenance','actions']
UNKNOWN='Non disponibile'

def get_entitlements(d):
 result=d.get('signing',{});s=result.get('stdout','')+result.get('stderr','');m=re.search(r'<\?xml.*?</plist>',s,re.S)
 if not m:m=re.search(r'<plist.*?</plist>',s,re.S)
 try:return plistlib.loads(m.group().encode()) if m else {}
 except Exception:return {}
def severity(x):
 s=x.get('severity',x.get('priority','')).lower()
 return 'Alta' if s.startswith('alta') else 'Media' if s.startswith('media') else 'Bassa' if s.startswith('bassa') else 'Da verificare'
def area(x):
 if '489' in x.get('cwe',''):return 'RESILIENCE'
 if '732' in x.get('cwe',''):return 'PLATFORM'
 if 'DATA' in x['id'] or x['id'] in ['MOCK','JWT']:return 'STORAGE / PRIVACY'
 if 'DEP' in x['id'] or 'GHSA' in x['id'] or x['id']=='NANOPB':return 'CODE / SUPPLY-CHAIN'
 return 'CODE'
def standard_platform(d,files,findings,dependencies,stripping,controls=None):
 findings=[x for x in findings if x.get('origin')=='cli']
 android=d['platform']=='Android';p='android' if android else 'ios';info=d.get('manifest',{}) if android else d.get('info',{})
 title=Path(d['input']).name;ent=get_entitlements(d) if not android else {}
 report={'schemaVersion':SCHEMA_VERSION,'platform':p,'title':title,'blocks':[]}
 def block(key,title,headers,rows,note=''):
  value={'key':key,'title':title,'headers':headers,'rows':rows,'note':note};report['blocks'].append(value);return value
 checks=[]
 def check(group,label,status,value):
  checks.append({'group':group,'check':label,'status':status,'value':value})
 if android:
  app=info.get('application',{});check('build','Accesso al debug','FAIL' if app.get('debuggable')=='true' else 'PASS',app.get('debuggable','false (default)'))
  check('build','Backup dei dati','WARN' if app.get('allowBackup','true')=='true' else 'PASS',app.get('allowBackup','true (default)'))
  check('network','Traffico in chiaro','WARN' if app.get('usesCleartextTraffic')=='true' else 'PASS' if app.get('usesCleartextTraffic')=='false' else 'UNKNOWN',app.get('usesCleartextTraffic',UNKNOWN))
  native=d.get('native',[]);bad=[x['path'] for x in native if x.get('bits')==64 and any(a<16384 for a in x.get('load_alignments',[]))]
  check('hardening','Compatibilità ELF 16 KB','FAIL' if bad else 'PASS' if native else 'UNKNOWN','; '.join(bad) or ('Nessuna incompatibilità osservata' if native else UNKNOWN))
  for field,label in [('nx_stack','Stack non eseguibile'),('relro','RELRO'),('bind_now','Bind now'),('stack_canary_import','Import stack canary')]:
   present=sum(x.get(field) is True for x in native)
   check('hardening',label,'PASS' if native and present==len(native) else 'WARN' if native else 'UNKNOWN',f'{present}/{len(native)} librerie; indicatore binario')
  alignment=d.get('zip_alignment',{})
  if alignment.get('exit') in (0,1):check('build','Allineamento ZIP 16 KB','PASS' if alignment['exit']==0 else 'FAIL','zipalign -c -P 16 -v 4')
  signature=d.get('signing',{})
  check('build','Firma APK','PASS' if signature.get('exit')==0 else 'UNKNOWN','Verificata' if signature.get('exit')==0 else UNKNOWN)
  certificate='Sviluppo' if re.search(r'Local Debug|Android Debug|OU=Development',signature.get('stdout',''),re.I) else 'Identità da verificare'
  check('build','Canale di firma','WARN' if certificate=='Sviluppo' else 'UNKNOWN',certificate)
  permissions=info.get('permissions',[]);sensitive=[x['name'] for x in permissions if any(t in x['name'] for t in ['CAMERA','RECORD_AUDIO','CONTACTS','LOCATION','CALENDAR','PHONE','EXTERNAL_STORAGE','BLUETOOTH_SCAN'])]
  block('permissions','Permessi sensibili',['Permission','maxSdkVersion','Classificazione'],[[x['name'],x.get('maxSdkVersion','—'),'Sensibile' if x['name'] in sensitive else 'Altra'] for x in permissions])
  block('components','Componenti riconosciuti nel pacchetto',['Componente','Tipo','Exported','Permission'],[[x.get('name'),x['type'],x.get('exported','Non esplicito'),x.get('permission','—')] for x in info.get('components',[])])
  block('dynamicModules','Moduli opzionali',['Dato','Valore'],[['Moduli on-demand',UNKNOWN],['Artefatto', 'APK; inventario AAB non disponibile']])
  block('hardening','Protezioni del codice',['File','NX stack','RELRO','Bind now','Canary import','PT_LOAD'],[[x['path'],x.get('nx_stack'),x.get('relro'),x.get('bind_now'),x.get('stack_canary_import'),str(x.get('load_alignments'))] for x in native])
  packages=dependencies.get('packages',[]);updates={x['coordinate']:x for x in dependencies.get('updates',[])}
  block('libraries','SDK esterne',['Libreria o gruppo','Versione inclusa','Ultima stabile','Stato'],[[x['package']['name'],x['version'],updates.get(x['package']['name'],{}).get('latest_stable',UNKNOWN),updates.get(x['package']['name'],{}).get('status','Versione dichiarata; aggiornamento non verificato')] for x in packages])
  advisories=[]
  results=dependencies.get('data',dependencies.get('results',{})).get('results',[])
  for package,result in zip(packages,results):
   for a in result.get('vulns',[]):advisories.append([package['package']['name'],package['version'],a['id'],'Da verificare','Candidato; raggiungibilità non verificata','Verificare prerequisiti e release corretta'])
  signature_id=info.get('package',UNKNOWN)
  build=info.get('build',UNKNOWN);version=info.get('version',UNKNOWN)
  library_count=len(packages);sens_count=len(sensitive)
 else:
  signature_id=info.get('CFBundleIdentifier',UNKNOWN);version=info.get('CFBundleShortVersionString',UNKNOWN);build=info.get('CFBundleVersion',UNKNOWN);frameworks=d.get('frameworks',[])
  check('build','Entitlement di debug','WARN' if ent.get('get-task-allow') else 'PASS' if ent else 'UNKNOWN',ent.get('get-task-allow',UNKNOWN))
  check('build','Firma bundle','PASS' if d.get('signature_verification',{}).get('exit')==0 else 'UNKNOWN','Verificata' if d.get('signature_verification',{}).get('exit')==0 else UNKNOWN)
  check('build','Condivisione documenti','WARN' if info.get('UIFileSharingEnabled') else 'PASS',info.get('UIFileSharingEnabled',False))
  ats=info.get('NSAppTransportSecurity',{})
  check('network','ATS arbitrary loads','WARN' if ats.get('NSAllowsArbitraryLoads') else 'PASS',ats.get('NSAllowsArbitraryLoads',False))
  check('network','ATS WebContent','WARN' if ats.get('NSAllowsArbitraryLoadsInWebContent') else 'PASS',ats.get('NSAllowsArbitraryLoadsInWebContent',False))
  main=d.get('main_macho',{})
  for field,label in [('has_pie','Posizione variabile del codice (PIE)'),('stack_canary_import','Import stack canary')]:check('hardening',label,'PASS' if main.get(field) else 'UNKNOWN',main.get(field,UNKNOWN))
  check('hardening','Gestione memoria ARC','UNKNOWN','Non attestata per l’intero bundle')
  development=[x['path'] for x in files if x['path'].endswith(('.dSYM','.swiftmodule','.swiftdoc'))]
  tests=[x['path'] for x in files if any(t in x['path'] for t in ['XCTest','TestRunner','.xctest'])]
  check('build','File di sviluppo','WARN' if development else 'PASS',len(development));check('build','Componenti di test','WARN' if tests else 'PASS',len(tests))
  manifests=d.get('privacy_manifests',[])
  fwrows=[]
  for fw in frameworks:
   matched=[x['path'] for x in manifests if x['path'].startswith(fw.get('path','Frameworks/'+fw['name'])+'/') or (fw['name'].removesuffix('.framework')+'.bundle/') in x['path']]
   fwrows.append([fw.get('path',fw['name']),len(matched),'Presente' if matched else 'Non individuato; obbligo da verificare'])
  block('privacy','Informazioni privacy dei componenti',['Componente','Manifest individuati','Stato'],fwrows,'Presenza e assenza non attestano conformità.')
  block('entitlements','Autorizzazioni dichiarate dall’app',['Autorizzazione','Valore'],[[k,json.dumps(v,ensure_ascii=False)] for k,v in ent.items()] or [['Entitlements',UNKNOWN]])
  block('permissions','Usage description',['Chiave','Valore'],[[k,v] for k,v in info.items() if k.endswith('UsageDescription')])
  block('hardening','Protezioni del codice',['Controllo','Esito','Valore'],[[x['check'],x['status'],x['value']] for x in checks if x['group']=='hardening'])
  sdkrows=[]
  for fw in frameworks:
   name=fw['name'].removesuffix('.framework');family='Firebase' if name.startswith('Firebase') else 'Facebook' if name.startswith(('FBSDK','FBAEM')) else name
   latest=dependencies.get(family,{}).get('latest',{}).get('data',{}).get('tag_name',UNKNOWN)
   used=fw['build'] if family=='Facebook' else fw['version']
   state='Versione placeholder / da confermare' if fw['version'] in ['0.0.1','1.0','1.0.0'] and family!='Facebook' else 'Versione dichiarata'
   resolution=dependencies.get(family,{}).get('resolution',{});upstream=resolution.get('upstream')
   current=numeric_version(str(latest));included=numeric_version(str(upstream or used))
   if current is not None and included is not None:state+='; aggiornamento disponibile' if current>included else '; allineata' if current==included else '; versione inclusa successiva alla release rilevata'
   if upstream:state+='; upstream '+upstream+' da podspec'
   sdkrows.append([fw.get('path',fw['name']),used,latest,state])
  block('libraries','SDK esterne',['Libreria o gruppo','Versione inclusa','Release corrente','Stato'],sdkrows)
  library_count=len(frameworks);sens_count=None;advisories=[]
  for name,dependency in dependencies.items():
   query=dependency.get('advisories',{})
   if query.get('status')==200 and isinstance(query.get('data'),list):
    for advisory in query['data']:
     if advisory.get('ghsa_id'):advisories.append([name,dependency.get('installed'),advisory['ghsa_id'],advisory.get('severity'),'Avviso pubblico del repository; applicabilità alla versione non attestata',advisory.get('summary')])
 records=advisory_records(d,dependencies)
 advisories=[[x['component'],x['installed'],x.get('matchedVersion'),x['id'],x.get('cve'),x.get('severity'),' / '.join(x.get('cwes',[])) or None,x.get('range'),x.get('patch'),x['limits'],x['url']] for x in records if x['state']!='excluded']
 excluded=[[x['component'],x['installed'],x.get('matchedVersion'),x['id'],x.get('range'),x['limits'],x['url']] for x in records if x['state']=='excluded']
 block('advisories','Sicurezza dei componenti',['Libreria','Versione inclusa','Versione confrontata','Avviso','CVE','Gravità','CWE','Intervallo interessato','Correzione indicata','Stato e limiti','Link'],advisories)
 block('excludedAdvisories','Advisory esclusi per versione',['Libreria','Versione inclusa','Versione confrontata','Avviso','Intervallo interessato','Esito','Link'],excluded)

 category_bytes=dict(d['categories'])
 if android:
  app_bytes=sum(x['bytes'] for x in files if x['path'].startswith('lib/') and x['path'].endswith('/libapp.so'))
  if app_bytes:category_bytes['native']-=app_bytes;category_bytes['app_aot']=app_bytes
 else:
  app_bytes=sum(x['bytes'] for x in files if x['path']==info.get('CFBundleExecutable'))
  if app_bytes:category_bytes['other']-=app_bytes;category_bytes['main']=app_bytes
 categories=[{'name':{'native':'Librerie native','dex':'Codice Android','frameworks':'Componenti software','flutter_assets':'Asset Flutter','android_resources':'Risorse Android','other':'Altre risorse','main':'Codice principale','app_aot':'Codice app Flutter AOT'}.get(k,k),'bytes':v} for k,v in category_bytes.items()]
 block('archiveContents','Contenuto del pacchetto',['Gruppo','Byte non compressi','Byte compressi','File'],[[x['group'],x['bytes'],x['compressed_bytes'],x['files']] for x in d.get('archive_contents',[])],'Payload: bundle analizzato. Gli altri gruppi sono contenuti esterni al bundle; la dimensione IPA include anche la struttura ZIP.')
 block('sizeBreakdown','Spazio per categoria',['Categoria','MiB','Quota %'],[[x['name'],round(x['bytes']/1048576,2),round(x['bytes']/d['uncompressed_bytes']*100,2) if d['uncompressed_bytes'] else 0] for x in categories])
 block('categories','Distribuzione dello spazio',['File','Byte','Categoria'],[[x['path'],x['bytes'],x['category']] for x in d['largest_files']])
 block('duplicates','File duplicati',['Percorsi','Copie','Byte per copia','Byte ridondanti'],[['; '.join(x['paths']),x['copies'],x['bytes_each'],x['redundant_bytes']] for x in d['duplicates']])
 block('deadCode','Codice potenzialmente inutilizzato',['Dato','Valore'],[['Elementi',UNKNOWN],['File',UNKNOWN],['Risparmio',UNKNOWN]])
 locales=sorted(set(m.group(1) for x in files for m in re.finditer(r'(?:^|/)([^/]+)\.lproj/',x['path'])))
 block('localization','Traduzioni',['Dato','Valore'],[['Directory .lproj',', '.join(locales) or 'Non individuate'],['Completezza stringhe',UNKNOWN],['Localizzazioni Flutter',UNKNOWN]])
 block('buildQuality','Configurazione della build',['Controllo','Esito','Valore'],[[x['check'],x['status'],x['value']] for x in checks if x['group']=='build'])
 block('connections','Connessioni e informazioni di debug',['Controllo','Esito','Valore'],[[x['check'],x['status'],x['value']] for x in checks if x['group']=='network'])
 assessment=[[x['id'],severity(x),area(x),x['title'],x.get('cwe','—'),x.get('status',UNKNOWN)+' · Priorità dichiarata: '+x.get('severity',x.get('priority',UNKNOWN)),x['evidence'],x.get('fix',UNKNOWN)] for x in findings]
 indicators=[[x['path'],', '.join(x.get('code_indicators',[]))] for x in d.get('scan',[]) if x.get('code_indicators')]
 block('codeIndicators','Indicatori statici del codice',['File','Simboli o stringhe'],indicators,'Presenza nel pacchetto; comportamento e raggiungibilità non dedotti.')
 block('assessment','Assessment Sicurezza',['ID','Priorità','Area','Tema','CWE','Stato','Evidenza','Intervento'],assessment)
 block('cwe','Controlli CWE',['CWE','Riscontro','Evidenza','Stato'],[[x['cwe'],x['title'],x['evidence'],x.get('status')] for x in findings if x.get('cwe') not in (None,'—')])
 block('maintenance','Altre verifiche e manutenzione',['Voce','Valore'],[['Stripping binari byte',sum(x['saving'] or 0 for x in stripping) if stripping and all(x['saving'] is not None for x in stripping) else UNKNOWN],['Asset web / mock','Vedere Assessment Sicurezza'],['Avvio / RAM / CPU / batteria',UNKNOWN],['Protezione nomi / offuscamento',UNKNOWN],['Compatibilità flussi / consenso privacy','Da verificare']])
 block('actions','Interventi da concordare',['Azione','Chi coinvolgere','Risultato da chiedere'],[[x.get('fix',UNKNOWN),'Team '+('Android' if android else 'iOS')+(' + Security' if x.get('cwe','—')!='—' else ''),x['id']+': evidenza sulla build corretta'] for x in findings])
 if not android:
  block('stripping','Informazioni di debug',['Binario','Byte prima','Risparmio byte','Stato'],[[x['path'],x['before'],x.get('saving'),x.get('status',x.get('exit',0))] for x in stripping])
 counts=collections.Counter(x['status'] for x in checks)
 report.update({'summary':{'date':d['audit_date'],'file':title,'identifier':signature_id,'version':version,'build':build,'packageBytes':d.get('package_bytes'),'contentBytes':d['uncompressed_bytes'],'installEstimate':None,'downloadEstimate':None,'files':d['file_count'],'libraries':library_count,'permissions':len(info.get('permissions',[])) if android else None,'sensitivePermissions':sens_count,'checks':dict(counts),'checksTotal':len(checks),'duplicateGroups':len(d['duplicates']),'duplicateBytes':d['duplicate_redundant_bytes'],'privacyManifests':len(d.get('privacy_manifests',[])) if not android else None,'findings':len(findings),'advisories':len(advisories),'exploitsConfirmed':0,'runtimeCoverage':UNKNOWN},'charts':{'categories':categories,'severity':[{'name':k,'count':sum(severity(x)==k for x in findings)} for k in ['Alta','Media','Bassa','Da verificare']],'areas':[{'name':k,'count':sum(k in area(x).split(' / ') for x in findings)} for k in ['STORAGE','CRYPTO','AUTH','NETWORK','PLATFORM','CODE','RESILIENCE','PRIVACY','SUPPLY-CHAIN']]},'checks':checks})
 summary=report['summary']
 for status in ['PASS','WARN','FAIL','NA','UNKNOWN']:summary['checks'].setdefault(status,0)
 block('summary','Versione e indicatori',['Dato','Valore'],[['Data',summary['date']],['Artefatto',summary['file']],['Identificativo',summary['identifier']],['Versione',summary['version']],['Build',summary['build']],['Dimensione pacchetto byte',summary['packageBytes']],['Contenuto logico byte',summary['contentBytes']],['Installazione stimata',summary['installEstimate']],['Download stimato',summary['downloadEstimate']],['File',summary['files']],['Librerie / componenti',summary['libraries']],['Riscontri',summary['findings']],['Exploit confermati',summary['exploitsConfirmed']]])
 report['blocks'].insert(0,report['blocks'].pop())
 # Present only automatically obtained data; unavailable checks remain in raw evidence.
 report['checks']=[x for x in report['checks'] if x['status']!='UNKNOWN']
 summary['checks']=dict(collections.Counter(x['status'] for x in report['checks']))
 summary['checksTotal']=len(report['checks'])
 for key in ['installEstimate','downloadEstimate','exploitsConfirmed','runtimeCoverage']:summary.pop(key,None)
 report['summary']={k:v for k,v in summary.items() if v is not None and v!=UNKNOWN}
 unavailable_keys={'deadCode','dynamicModules'}
 unavailable_summary={'Installazione stimata','Download stimato','Exploit confermati'}
 unavailable_maintenance={'Avvio / RAM / CPU / batteria','Protezione nomi / offuscamento','Compatibilità flussi / consenso privacy'}
 cleaned=[]
 for value in report['blocks']:
  key=value['key']
  if key in unavailable_keys:continue
  rows=value['rows']
  if key in ('buildQuality','hardening','connections'):
   rows=[r for r in rows if 'UNKNOWN' not in r]
  if key=='summary':rows=[r for r in rows if r[0] not in unavailable_summary and r[1] is not None and r[1]!=UNKNOWN]
  if key=='maintenance':rows=[r for r in rows if r[0] not in unavailable_maintenance and r[1]!=UNKNOWN]
  if key=='localization':rows=[r for r in rows if r[0]=='Directory .lproj']
  rows=[r for r in rows if any(v is not None and v not in (UNKNOWN,'Non applicabile ad Android') for v in r[1:])]
  if not rows and key not in ('assessment','actions'):continue
  # Omit entirely unavailable columns; missing cells in mixed inventories use a dash.
  headers=value['headers']
  columns=[i for i in range(len(headers)) if any(r[i] is not None and r[i]!=UNKNOWN for r in rows)] if rows else list(range(len(headers)))
  if columns:value['headers']=[headers[i] for i in columns];value['rows']=[[None if r[i]==UNKNOWN else r[i] for i in columns] for r in rows]
  else:continue
  cleaned.append(value)
 report['blocks']=cleaned

 return report

STYLE='\n  :root {\n    --bg: #f4f6fb;\n    --surface: #ffffff;\n    --surface-alt: #f8fafc;\n    --border: #e2e8f0;\n    --text: #0f172a;\n    --text-muted: #64748b;\n    --radius-lg: 24px;\n    --radius-md: 14px;\n    --shadow: 0 8px 24px rgba(15, 23, 42, 0.06), 0 2px 6px rgba(15, 23, 42, 0.04);\n    --accent-1: #2563eb;\n    --accent-2: #7c3aed;\n    --accent-3: #ec4899;\n    --positive: #10b981;\n    --positive-soft: #d1fae5;\n    --negative: #dc2626;\n    --negative-soft: #fee2e2;\n    --warning: #f97316;\n    --warning-soft: #ffedd5;\n    --info: #0ea5e9;\n    --info-soft: #e0f2fe;\n    --neutral-soft: #e2e8f0;\n    --sev-critical: #b00020;\n    --sev-high: #d84315;\n    --sev-medium: #f57c00;\n    --sev-low: #c9a400;\n    --sev-info: #64748b;\n  }\n  @media (prefers-color-scheme: dark) {\n    :root {\n      --bg: #0b1220;\n      --surface: #131b2c;\n      --surface-alt: #1a2436;\n      --border: #253045;\n      --text: #e2e8f0;\n      --text-muted: #94a3b8;\n      --shadow: 0 8px 24px rgba(0, 0, 0, 0.35), 0 2px 6px rgba(0, 0, 0, 0.25);\n      --positive-soft: #06301f;\n      --negative-soft: #3a1414;\n      --warning-soft: #3a2408;\n      --info-soft: #072a3a;\n      --neutral-soft: #202b3f;\n    }\n  }\n  * { box-sizing: border-box; }\n  body {\n    margin: 0;\n    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;\n    background: var(--bg);\n    color: var(--text);\n    line-height: 1.5;\n  }\n  header.hero {\n    background: linear-gradient(120deg, var(--accent-1), var(--accent-2) 55%, var(--accent-3));\n    color: #fff;\n    padding: 36px 28px 28px;\n  }\n  header.hero h1 { margin: 0 0 6px; font-size: 26px; font-weight: 700; }\n  header.hero p { margin: 0; opacity: 0.9; font-size: 14px; }\n  .hero-meta { display: flex; gap: 22px; flex-wrap: wrap; margin-top: 16px; font-size: 13px; opacity: 0.95; }\n  .hero-meta span b { display: block; font-size: 15px; }\n\n  nav.tabs {\n    position: sticky; top: 0; z-index: 20;\n    display: flex; gap: 4px; overflow-x: auto;\n    background: var(--surface); border-bottom: 1px solid var(--border);\n    padding: 0 20px;\n  }\n  nav.tabs button {\n    border: none; background: none; cursor: pointer;\n    padding: 14px 16px; font-size: 14px; font-weight: 600;\n    color: var(--text-muted); white-space: nowrap;\n    border-bottom: 3px solid transparent;\n  }\n  nav.tabs button.active { color: var(--accent-1); border-bottom-color: var(--accent-1); }\n  nav.tabs button:hover { color: var(--accent-1); }\n\n  main { max-width: 1280px; margin: 0 auto; padding: 24px 20px 60px; }\n  .tab-content { display: none; }\n  .tab-content.active { display: block; }\n\n  .grid { display: grid; gap: 16px; }\n  .grid-kpi { grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); margin-bottom: 20px; }\n  .grid-2 { grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); }\n  .platform-row-label { font-size: 13px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; margin: 0 0 10px; }\n  .grid-3 { grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }\n\n  .card {\n    background: var(--surface); border: 1px solid var(--border);\n    border-radius: var(--radius-lg); padding: 20px; box-shadow: var(--shadow);\n  }\n  .card h3 { margin: 0 0 14px; font-size: 15px; font-weight: 700; }\n  .card h3 .muted { color: var(--text-muted); font-weight: 500; font-size: 12px; }\n\n  .kpi .kpi-label { font-size: 12px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.04em; }\n  .kpi .kpi-value { font-size: 28px; font-weight: 800; margin: 6px 0 4px; }\n  .kpi .kpi-sub { font-size: 12px; color: var(--text-muted); }\n\n  .badge {\n    display: inline-block; padding: 2px 10px; border-radius: 999px;\n    font-size: 11px; font-weight: 700; letter-spacing: 0.02em; color: #fff;\n  }\n  .badge-PASS { background: var(--positive); }\n  .badge-WARN { background: var(--warning); color: #1a1a1a; }\n  .badge-FAIL { background: var(--negative); }\n  .badge-Critical { background: var(--sev-critical); }\n  .badge-High { background: var(--sev-high); }\n  .badge-Medium { background: var(--sev-medium); color: #1a1a1a; }\n  .badge-Low { background: var(--sev-low); color: #1a1a1a; }\n  .badge-Info { background: var(--sev-info); }\n  .badge-RED { background: var(--negative); }\n  .badge-GREEN { background: var(--positive); }\n  .badge-YELLOW { background: var(--warning); color: #1a1a1a; }\n  .badge-ok { background: var(--positive); }\n  .badge-minor { background: #eab308; color:#1a1a1a; }\n  .badge-warn { background: var(--warning); color: #1a1a1a; }\n  .badge-critical { background: var(--negative); }\n  .badge-unknown { background: var(--text-muted); }\n  .badge-NA { background: var(--text-muted); }\n  .badge-high { background: var(--sev-high); }\n  .badge-medium { background: var(--sev-medium); color: #1a1a1a; }\n  .badge-low { background: var(--sev-low); color: #1a1a1a; }\n\n  .alert {\n    border-radius: var(--radius-md); padding: 16px 18px; margin: 18px 0;\n    display: flex; gap: 12px; align-items: flex-start; font-size: 13.5px;\n  }\n  .alert-warning { background: var(--warning-soft); border: 1px solid var(--warning); }\n  .alert-info { background: var(--info-soft); border: 1px solid var(--info); }\n  .alert .icon { font-size: 20px; line-height: 1; }\n  .alert b.lead { display: block; margin-bottom: 4px; }\n\n  section.tab-section { margin-bottom: 26px; }\n  section.tab-section > h2 { font-size: 18px; margin: 0 0 12px; }\n\n  table { width: 100%; border-collapse: collapse; font-size: 13px; }\n  thead th {\n    text-align: left; padding: 8px 10px; background: var(--surface-alt);\n    border-bottom: 2px solid var(--border); cursor: pointer; user-select: none;\n    position: sticky; top: 0;\n  }\n  thead th:hover { color: var(--accent-1); }\n  tbody td { padding: 7px 10px; border-bottom: 1px solid var(--border); vertical-align: top; }\n  tbody tr:hover { background: var(--surface-alt); }\n  .table-scroll { max-height: 480px; overflow: auto; border: 1px solid var(--border); border-radius: var(--radius-md); }\n\n  .table-toolbar { display: flex; gap: 10px; align-items: center; margin-bottom: 10px; flex-wrap: wrap; }\n  .table-toolbar input[type="search"] {\n    padding: 8px 12px; border-radius: 999px; border: 1px solid var(--border);\n    background: var(--surface-alt); color: var(--text); font-size: 13px; min-width: 220px;\n  }\n  .table-toolbar .count { font-size: 12px; color: var(--text-muted); margin-left: auto; }\n  .chip-btn {\n    border: 1px solid var(--border); background: var(--surface-alt); color: var(--text);\n    padding: 6px 12px; border-radius: 999px; font-size: 12px; cursor: pointer; font-weight: 600;\n    text-decoration: none; display: inline-block;\n  }\n  .chip-btn.active { background: var(--accent-1); color: #fff; border-color: var(--accent-1); }\n  .jump-nav { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 20px; }\n  section[id], h2[id] { scroll-margin-top: 66px; }\n\n  .checklist { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }\n  .checklist .item { padding: 10px 12px; border: 1px solid var(--border); border-radius: var(--radius-md); background: var(--surface-alt); }\n  .checklist .item .head { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-bottom: 4px; }\n  .checklist .item .title { font-weight: 700; font-size: 13px; }\n  .checklist .item .detail { font-size: 12px; color: var(--text-muted); }\n\n  .chip-list { display: flex; flex-wrap: wrap; gap: 6px; }\n  .chip-list .chip { background: var(--neutral-soft); padding: 4px 10px; border-radius: 999px; font-size: 11.5px; font-family: ui-monospace, monospace; }\n\n  .stat-bar { height: 10px; border-radius: 999px; background: var(--neutral-soft); overflow: hidden; display: flex; }\n  .stat-bar span { display: block; height: 100%; }\n\n  footer.note { font-size: 11.5px; color: var(--text-muted); margin-top: 30px; padding-top: 16px; border-top: 1px solid var(--border); }\n\n  .accordion-tabs { display: flex; gap: 8px; margin-bottom: 14px; flex-wrap: wrap; }\n\n  canvas { max-width: 100%; }\n\n  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }\n  @media (max-width: 720px) { .two-col { grid-template-columns: 1fr; } }\n\n  .insight-list { padding-left: 18px; }\n  .insight-list li { margin-bottom: 10px; font-size: 13.5px; }\n/* The supplied template retains its hero, four tabs, KPI rows and chart/table grids. */\n:root{--bg:#f2f5f3;--surface:#fff;--surface-alt:#f7f9f8;--border:#d7e1db;--text:#253b31;--text-muted:#58695f;--radius-lg:10px;--radius-md:7px;--shadow:none;--accent-1:#32694f;--accent-2:#32694f;--accent-3:#32694f;--positive:#32694f;--positive-soft:#e6f1e9;--negative:#a83b48;--negative-soft:#f9ebed;--warning:#8e6d2d;--warning-soft:#f7f1e3;--info:#416e80;--info-soft:#eaf1f3;--neutral-soft:#e8eeea;--sev-critical:#a83b48;--sev-high:#996131;--sev-medium:#876d26;--sev-low:#416e80;color-scheme:light}\n@media(prefers-color-scheme:dark){:root{--bg:#14201d;--surface:#1d2b26;--surface-alt:#22342c;--border:#3b4c42;--text:#eff4f0;--text-muted:#b6c7bc;--shadow:none;--accent-1:#a4cfb7;--positive:#a4cfb7;--positive-soft:#243e30;--negative:#f4a6ac;--negative-soft:#442c30;--warning:#e0c48d;--warning-soft:#3c3526;--info:#afced9;--info-soft:#233842;--neutral-soft:#34483c;color-scheme:dark}}\nbody{font-family:\'Avenir Next\',Avenir,-apple-system,BlinkMacSystemFont,\'Segoe UI\',sans-serif;font-size:15px;line-height:1.6}header.hero{background:#254d3c;border-bottom:1px solid #51755e;padding:30px max(24px,calc((100vw - 1240px)/2)) 26px;color:#fff}header.hero h1{font-size:28px;font-weight:650;letter-spacing:-.025em}header.hero p{font-size:15px;max-width:85ch}.hero-meta{gap:34px}.hero-meta span b{font-size:15px;font-weight:600}.hero-meta span{font-size:12px;color:#e4eee8}nav.tabs{padding:0 max(20px,calc((100vw - 1240px)/2));gap:8px}nav.tabs button{font:600 14px inherit;padding:14px 16px;border-bottom-width:2px}main{padding-top:26px;max-width:1280px}.card{box-shadow:none;padding:21px;border-radius:10px;min-width:0}.card h3{font-size:16px;font-weight:600;margin-bottom:16px;line-height:1.45}.grid-kpi{grid-template-columns:repeat(6,minmax(0,1fr));gap:12px}.kpi{padding:17px 15px}.kpi .kpi-label{font-size:12px;text-transform:none;letter-spacing:0;line-height:1.4;min-height:34px}.kpi .kpi-value{font-size:24px;font-weight:650;line-height:1.25;margin:9px 0;letter-spacing:-.025em;font-variant-numeric:tabular-nums;overflow-wrap:break-word}.kpi .kpi-sub{font-size:12px;line-height:1.55}.platform-row-label{font-size:15px;color:var(--text);text-transform:none;letter-spacing:0;margin:4px 0 12px;font-weight:650}.platform-row-label:not(:first-child){margin-top:25px}.grid-2{grid-template-columns:repeat(2,minmax(0,1fr))}.grid-3{grid-template-columns:repeat(3,minmax(0,1fr))}.platform-charts{margin-bottom:26px}.platform-charts>.card:nth-child(4){grid-column:1}.alert{border-radius:7px;border-width:0 0 0 3px;padding:15px 18px;line-height:1.7}.alert b.lead{font-weight:650}.alert .icon{display:none}.badge{font-size:11px;padding:3px 8px;border-radius:4px;letter-spacing:0;font-weight:600;white-space:normal;line-height:1.5}.badge-PASS{color:var(--positive);background:var(--positive-soft)}.badge-WARN{color:var(--warning);background:var(--warning-soft)}.badge-FAIL{color:var(--negative);background:var(--negative-soft)}.badge-critical,.badge-high,.badge-medium,.badge-low{color:#fff}.badge-critical{background:#a83b48}.badge-high{background:#8d572b}.badge-medium{background:#796322}.badge-low{background:#416e80}.badge-unrated{color:var(--text-muted);background:var(--neutral-soft)}.badge-neutral{background:var(--neutral-soft);color:var(--text)}.small{font-size:12px;line-height:1.7}.muted{color:var(--text-muted)}a{color:var(--accent-1);text-underline-offset:3px}.card p{max-width:90ch}.chart-frame{position:relative;min-width:0}.chart-frame canvas{width:100%!important;height:100%!important}.table-scroll{max-width:100%;max-height:440px;scrollbar-width:thin;scrollbar-color:var(--text-muted) transparent}.table-scroll table{min-width:620px;line-height:1.6}.table-scroll:has(th:nth-child(5)) table{min-width:1100px}.table-scroll td,.table-scroll th{padding:10px 12px;overflow-wrap:break-word;max-width:420px}.table-scroll th{font-weight:600;z-index:1}.table-scroll td small{display:block;line-height:1.65;margin-top:6px;color:var(--text-muted)}.table-scroll td a{overflow-wrap:anywhere}.table-toolbar input[type=search]{border-radius:6px;min-width:0;width:240px;max-width:100%;font:inherit;font-size:13px}.chip-btn{border-radius:6px;font-family:inherit;font-size:13px;padding:7px 12px}.chip-btn.active{background:var(--surface-alt);color:var(--accent-1);border-color:var(--accent-1)}.chip-list .chip{font-family:inherit;font-size:12px;border-radius:4px;overflow-wrap:anywhere}.checklist{grid-template-columns:1fr}.checklist .item{border-radius:6px}.checklist .head{align-items:flex-start}.checklist .detail{font-size:13px;line-height:1.65}.stat-bar{border-radius:2px}.insight-list li{font-size:14px;line-height:1.8;margin-bottom:18px}.insight-list{padding-left:20px;max-width:105ch}section.tab-section>h2,#ios-vapt{font-size:20px;font-weight:600;letter-spacing:-.015em}details{padding:14px 0;border-top:1px solid var(--border);margin-top:14px}summary{cursor:pointer;font-weight:600;font-size:14px;line-height:1.65}details[open]>summary{margin-bottom:14px}.skip-link{position:absolute;top:-100px;left:20px;z-index:100;padding:12px;background:var(--surface);color:var(--text)}.skip-link:focus{top:10px}:focus-visible{outline:3px solid var(--accent-1);outline-offset:3px}button,input,a,summary{-webkit-tap-highlight-color:transparent}footer.note{font-size:12px;line-height:1.8}.source-hash{overflow-wrap:anywhere}#sourceTable td:last-child{word-break:break-all}\n@media(max-width:1100px){.grid-kpi{grid-template-columns:repeat(3,minmax(0,1fr))}.kpi .kpi-label{min-height:0}.grid-3{grid-template-columns:repeat(2,minmax(0,1fr))}}\n@media(max-width:720px){header.hero{padding:23px 20px}header.hero h1{font-size:25px}.hero-meta{gap:15px 24px}main{padding:20px 14px 40px}nav.tabs{padding:0 10px;gap:0}nav.tabs button{padding:14px 12px;font-size:13px}.grid-2,.grid-3{grid-template-columns:minmax(0,1fr)}.grid-kpi{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.card{padding:18px}.kpi{padding:15px}.kpi .kpi-value{font-size:24px}.table-toolbar{gap:8px}.table-toolbar input[type=search]{width:100%}.table-toolbar .count{margin-left:0}.platform-charts>.card:nth-child(4){grid-column:auto}.jump-nav{gap:6px}.chart-frame{height:280px}.checklist .head{flex-wrap:wrap}.hero-meta span{max-width:100%}.table-scroll:before{content:\'Scorri la tabella per leggere tutte le colonne\';display:block;position:sticky;left:0;font-size:11px;padding:7px 10px;color:var(--text-muted);background:var(--surface-alt);width:100%}}\n@media(prefers-reduced-motion:reduce){*,*:before,*:after{scroll-behavior:auto!important;animation:none!important;transition:none!important}}\n@media print{header.hero{background:white;color:black;padding:12px 0}header.hero p,.hero-meta span{color:black}nav.tabs,.skip-link,.table-toolbar,.jump-nav{display:none}body{background:white;color:black}.card{break-inside:avoid;box-shadow:none}.table-scroll{max-height:none;overflow:visible}.table-scroll table{min-width:0}main{max-width:none;padding:10px 0}.grid-kpi{grid-template-columns:repeat(3,1fr)}.grid-3,.grid-2{grid-template-columns:repeat(2,1fr)}.alert{color:black;background:#eee}.muted{color:#444}}\n\n.bar-row{display:grid;grid-template-columns:minmax(110px,1.2fr) 2fr auto;gap:12px;align-items:center;margin:10px 0;font-size:12px}.bar-row b{font-size:11px}.donut-chart{display:grid;grid-template-columns:180px 1fr;gap:14px;align-items:center}.donut-chart svg{width:180px}.legend-row{font-size:12px;margin:7px 0}.legend-row span{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:7px}.legend-row b{float:right}.muted{color:var(--text-muted)}.small{font-size:12px}.table-scroll td{overflow-wrap:anywhere;max-width:360px;min-width:100px}@media(max-width:720px){.grid-2,.grid-3{grid-template-columns:1fr}.donut-chart{grid-template-columns:130px 1fr}.donut-chart svg{width:130px}.bar-row{grid-template-columns:100px 1fr auto}}@media print{.tab-content{display:block!important}.tab-content[hidden]{display:block!important}.table-scroll{max-height:none;overflow:visible}.tabs,.table-toolbar{display:none}.card{box-shadow:none}}'
SCRIPT=r'''(function(){
'use strict';
const esc=x=>String(x??'—').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const val=x=>x===null||x===undefined?'—':typeof x==='boolean'?(x?'Sì':'No'):typeof x==='string'&&/^https:\/\/[^\s]+$/.test(x)?'<a href="'+esc(x)+'" target="_blank" rel="noopener noreferrer">Apri</a>':esc(x);
const num=x=>x===null||x===undefined?'—':new Intl.NumberFormat('it-IT',{maximumFractionDigits:2}).format(x);
const mib=x=>x===null||x===undefined?'—':num(x/1048576)+' MiB';
const colors=['#42856a','#7c9aaa','#b39355','#78826f','#a5bdb1','#617186','#9e887c','#7c9a8d'];
const names={PASS:'Superato',WARN:'Da approfondire',FAIL:'Non superato',NA:'Non applicabile',UNKNOWN:'Non disponibile'};
const badge=(v)=>`<span class="badge badge-${['PASS','FAIL','WARN','NA'].includes(v)?v:'unknown'}">${esc(names[v]||v)}</span>`;
const semanticColor=(x,i)=>({'Alta':'#d84315','Media':'#f57c00','Bassa':'#c9a400','Da verificare':'#64748b','Superato':'#10b981','Da approfondire':'#f97316','Non superato':'#dc2626','Non applicabile':'#64748b','Non disponibile':'#64748b'}[x.name]||colors[i%colors.length]);
let counter=0;
const pending=[];
function card(label,value,sub=''){return `<div class="card kpi"><div class="kpi-label">${esc(label)}</div><div class="kpi-value">${value}</div><div class="kpi-sub">${esc(sub)}</div></div>`;}
function table(block){const id='table-'+(++counter);pending.push([id,block]);return `<div id="${id}"></div>`;}
function buildTable(container,block){
 let data=block.rows||[],filter='',sort=-1,dir=1,selected='Tutte';
 const severityIndex=block.key==='assessment'?block.headers.indexOf('Priorità'):-1;
 container.innerHTML='<div class="table-toolbar"><input type="search" placeholder="Cerca…" aria-label="Cerca nella tabella '+esc(block.title)+'"><span class="count" aria-live="polite"></span></div>'+(severityIndex>=0?'<div class="accordion-tabs">'+['Tutte','Alta','Media','Bassa','Da verificare'].map(x=>'<button class="chip-btn '+(x==='Tutte'?'active':'')+'" data-severity="'+esc(x)+'" aria-pressed="'+(x==='Tutte')+'">'+esc(x)+'</button>').join('')+'</div>':'')+'<div class="table-scroll" tabindex="0" role="region" aria-label="'+esc(block.title)+'"><table><thead><tr>'+block.headers.map((x,i)=>'<th scope="col" tabindex="0" data-index="'+i+'">'+esc(x)+'</th>').join('')+'</tr></thead><tbody></tbody></table></div>';
 const render=()=>{
  let rows=data.filter(r=>r.some(v=>String(v??'').toLowerCase().includes(filter))&&(selected==='Tutte'||r[severityIndex]===selected));
  if(sort>=0)rows=rows.slice().sort((a,b)=>dir*(typeof a[sort]==='number'&&typeof b[sort]==='number'?a[sort]-b[sort]:String(a[sort]??'').localeCompare(String(b[sort]??''),'it')));
  container.querySelector('tbody').innerHTML=rows.length?rows.map(r=>'<tr>'+r.map((x,i)=>'<td>'+(block.headers[i]==='Priorità'?'<span class="badge badge-'+({'Alta':'High','Media':'Medium','Bassa':'Low'}[x]||'unknown')+'">'+esc(x)+'</span>':['Esito','Stato verifica'].includes(block.headers[i])&&names[x]?badge(x):val(x))+'</td>').join('')+'</tr>').join(''):'<tr><td colspan="'+block.headers.length+'">'+(data.length?'Nessun risultato':'Nessun record attestato')+'</td></tr>';
  container.querySelector('.count').textContent=num(rows.length)+' voci';
 };
 container.querySelector('input').addEventListener('input',e=>{filter=e.target.value.toLowerCase();render();});
 container.querySelectorAll('th').forEach(th=>{
  const order=()=>{const i=+th.dataset.index;dir=sort===i?-dir:1;sort=i;container.querySelectorAll('th').forEach(x=>x.removeAttribute('aria-sort'));th.setAttribute('aria-sort',dir===1?'ascending':'descending');render();};
  th.addEventListener('click',order);th.addEventListener('keydown',e=>{if(['Enter',' '].includes(e.key)){e.preventDefault();order();}});
 });
 container.querySelectorAll('[data-severity]').forEach(b=>b.addEventListener('click',()=>{selected=b.dataset.severity;container.querySelectorAll('[data-severity]').forEach(x=>{x.classList.toggle('active',x===b);x.setAttribute('aria-pressed',String(x===b));});render();}));
 render();
}
function flush(){while(pending.length){const [id,b]=pending.shift();const node=document.getElementById(id);if(node)buildTable(node,b);}}
function bar(title,data,unit='voci'){
 const max=Math.max(...data.map(x=>x.value),1);
 return '<div class="card"><h3>'+esc(title)+'</h3><div class="bar-chart" role="img" aria-label="'+esc(data.map(x=>x.name+': '+num(x.value)+' '+unit).join('; '))+'">'+data.map((x,i)=>'<div class="bar-row"><span>'+esc(x.name)+'</span><div class="stat-bar"><span style="width:'+x.value/max*100+'%;background:'+semanticColor(x,i)+'"></span></div><b>'+num(x.value)+' '+esc(unit)+'</b></div>').join('')+'</div></div>';
}
function donut(title,data,unit='voci'){
 const total=data.reduce((a,x)=>a+x.value,0);let offset=0;const c=2*Math.PI*72;
 const slices=data.map((x,i)=>{const len=total?x.value/total*c:0;const svg='<circle cx="110" cy="110" r="72" fill="none" stroke="'+semanticColor(x,i)+'" stroke-width="27" stroke-dasharray="'+len+' '+(c-len)+'" stroke-dashoffset="'+(-offset)+'" transform="rotate(-90 110 110)"/>';offset+=len;return svg;}).join('');
 return '<div class="card"><h3>'+esc(title)+'</h3><div class="donut-chart"><svg viewBox="0 0 220 220" role="img" aria-label="'+esc(data.map(x=>x.name+': '+num(x.value)+' '+unit).join('; '))+'"><circle cx="110" cy="110" r="72" fill="none" stroke="var(--neutral-soft)" stroke-width="27"/>'+slices+'<text x="110" y="108" text-anchor="middle" fill="var(--text)" font-size="23" font-weight="700">'+num(total)+'</text><text x="110" y="131" text-anchor="middle" fill="var(--text-muted)" font-size="12">'+esc(unit)+'</text></svg><div>'+data.map((x,i)=>'<div class="legend-row"><span style="background:'+semanticColor(x,i)+'"></span>'+esc(x.name)+' <b>'+num(x.value)+'</b></div>').join('')+'</div></div></div>';
}
function blockFor(p,key){return p.blocks.find(x=>x.key===key);}
function section(p,key,details=false){const b=blockFor(p,key);if(!b)return '';return '<section class="tab-section" id="'+p.platform+'-'+key+'">'+(details?'<details><summary>'+esc(b.title)+'</summary>':'<h2>'+esc(b.title)+'</h2>')+'<div class="card">'+(b.note?'<p class="small muted">'+esc(b.note)+'</p>':'')+table(b)+'</div>'+(details?'</details>':'')+'</section>';}
function checklist(title,items){return '<div class="card"><h3>'+esc(title)+'</h3><div class="checklist">'+items.map(x=>'<div class="item"><div class="head"><span class="title">'+esc(x.check)+'</span>'+badge(x.status)+'</div><div class="detail">'+val(x.value)+'</div></div>').join('')+'</div></div>';}
function platformKpis(p){const s=p.summary;const cards=[];if(s.version!==undefined)cards.push(card('Versione analizzata',esc(s.version),s.build!==undefined?'Build '+s.build:''));if(s.packageBytes!==undefined)cards.push(card('Dimensione del pacchetto',mib(s.packageBytes),s.file));cards.push(card('Contenuto logico',mib(s.contentBytes),'Somma dei file'));cards.push(card('File analizzati',num(s.files),s.identifier));cards.push(card('Controlli superati',num(s.checks.PASS||0)+' / '+num(s.checksTotal),num(s.checks.WARN||0)+' da approfondire · '+num(s.checks.FAIL||0)+' non superati'));return '<div class="grid grid-kpi">'+cards.join('')+'</div>';}

function downloads(p){const l=DATA.links[p]||{};return '<section class="tab-section"><div class="card"><h3>Report completo per il team</h3><div class="jump-nav">'+[['pdf','Scarica PDF'],['json','Dati JSON'],['csv','Duplicati CSV'],['unified','Report unificato']].filter(([k])=>l[k]).map(([k,label])=>'<a class="chip-btn" href="'+esc(l[k])+'"'+(k==='pdf'?' download':'')+'>'+label+'</a>').join('')+'</div></div></section>';}
function renderRecap(){
 const platforms=Object.values(DATA.platforms);
 let body='';
 platforms.forEach(p=>{body+='<section class="tab-section"><p class="platform-row-label">'+(p.platform==='ios'?'iOS':'Android')+'</p>'+platformKpis(p)+'<div class="grid grid-3">'+bar('Spazio per categoria',p.charts.categories.map(x=>({name:x.name,value:Math.round(x.bytes/1048576*100)/100})),'MiB')+donut('Distribuzione dello spazio',p.charts.categories.map(x=>({name:x.name,value:Math.round(x.bytes/1048576*100)/100})),'MiB')+donut('Controlli della build',Object.entries(p.summary.checks).map(([name,value])=>({name:names[name]||name,value})))+'</div></section>';});
 body+='<section class="tab-section"><div class="grid grid-2">'+bar('Dimensioni degli artefatti',platforms.map(p=>({name:p.platform==='ios'?'iOS · APP logica':'Android · APK',value:Math.round((p.summary.packageBytes??p.summary.contentBytes)/1048576*100)/100})),'MiB')+bar('Segnalazioni per priorità',platforms.flatMap(p=>p.charts.severity.map(x=>({name:p.platform+' · '+x.name,value:x.count}))))+'</div></section>';
 document.getElementById('tab-recap').innerHTML=body;flush();
}
function renderPlatform(key){
 const p=DATA.platforms[key];const root=document.getElementById('tab-'+key);
 if(!p){root.innerHTML='<div class="card"><h2>'+esc(key)+'</h2><p>Artefatto non disponibile in questo report.</p></div>';return;}
 const s=p.summary;
 let body='<div class="jump-nav">'+[['sizeBreakdown','Dimensioni'],['libraries','Componenti'],['advisories','Analisi Sicurezza'],['assessment','Assessment Sicurezza'],['buildQuality','Controlli']].filter(([id])=>blockFor(p,id)).map(([id,label])=>'<a class="chip-btn" href="#'+key+'-'+id+'">'+label+'</a>').join('')+'</div>'+platformKpis(p);
 body+='<section class="tab-section" id="'+key+'-sizeBreakdown"><h2>Dimensioni</h2><div class="grid grid-2">'+bar('Spazio per categoria',p.charts.categories.map(x=>({name:x.name,value:Math.round(x.bytes/1048576*100)/100})),'MiB')+donut('Distribuzione dello spazio',p.charts.categories.map(x=>({name:x.name,value:Math.round(x.bytes/1048576*100)/100})),'MiB')+'</div></section>';
 body+=section(p,'archiveContents')+section(p,'categories',true);
 const libs=blockFor(p,'libraries');
 const counts={};if(libs)libs.rows.forEach(r=>{const state=r[libs.headers.indexOf('Stato')];counts[state]=(counts[state]||0)+1;});
 if(libs)body+='<section class="tab-section" id="'+key+'-libraries"><h2>SDK esterne</h2><div class="grid grid-2">'+bar('Disponibilità delle versioni',Object.entries(counts).map(([name,value])=>({name,value})))+'<div class="card"><h3>Inventario consultabile</h3>'+table(libs)+'</div></div></section>';
 body+=section(p,'advisories')+section(p,'excludedAdvisories',true)+section(p,'codeIndicators',true);
 body+='<section class="tab-section" id="'+key+'-assessment"><h2>Assessment Sicurezza</h2><div class="grid grid-kpi">'+card('Periodo analizzato',esc(s.date))+card('Segnalazioni rilevate',num(s.findings),'Priorità qualitative; sfruttabilità non confermata')+card('Aree con segnalazioni',num(p.charts.areas.filter(x=>x.count).length),'Nessuna percentuale di conformità')+'</div><div class="grid grid-2">'+bar('Gravità dei finding rilevati',p.charts.severity.map(x=>({name:x.name,value:x.count})))+bar('Segnalazioni per area di controllo',p.charts.areas.map(x=>({name:x.name,value:x.count})))+'</div><div class="card">'+table(blockFor(p,'assessment'))+'</div></section>';
 body+=section(p,'cwe')+section(p,'actions')+section(p,'duplicates');
 body+=key==='ios'?section(p,'privacy')+section(p,'localization')+section(p,'deadCode')+section(p,'entitlements')+section(p,'stripping',true):section(p,'permissions')+section(p,'components')+section(p,'dynamicModules')+section(p,'deadCode');
 body+='<section class="tab-section" id="'+key+'-buildQuality"><h2>Configurazione della build</h2><div class="grid grid-2">'+checklist('Controlli della build',p.checks.filter(x=>x.group==='build'))+checklist('Protezioni del codice',p.checks.filter(x=>x.group==='hardening'))+'</div></section>';
 body+=section(p,'hardening',true)+section(p,'connections')+section(p,'maintenance')+downloads(key);
 root.innerHTML=body;flush();
}
function renderInsights(){
 const platforms=Object.values(DATA.platforms);
 const summary={key:'insights',title:'Indicatori ottenuti',headers:['Piattaforma','File','Riscontri','Duplicati ridondanti (byte)'],rows:platforms.map(p=>[p.platform,p.summary.files,p.summary.findings,p.summary.duplicateBytes])};
 const actions={key:'actions',title:'Azioni e risultati da chiedere',headers:['Piattaforma','Azione','Chi coinvolgere','Risultato'],rows:platforms.flatMap(p=>blockFor(p,'actions').rows.map(r=>[p.platform,...r]))};
 document.getElementById('tab-insights').innerHTML='<section class="tab-section"><h2>Indicatori ottenuti</h2><div class="card">'+table(summary)+'</div></section><section class="tab-section"><h2>Azioni e risultati da chiedere</h2><div class="card">'+table(actions)+'</div></section>';flush();
}
document.querySelectorAll('#tabNav button').forEach(b=>{if(['ios','android'].includes(b.dataset.tab)&&!DATA.platforms[b.dataset.tab]){b.remove();document.getElementById('tab-'+b.dataset.tab).remove();}});
const rendered=new Set();const buttons=[...document.querySelectorAll('#tabNav button')];
function activate(key){buttons.forEach(b=>{const on=b.dataset.tab===key;b.classList.toggle('active',on);b.setAttribute('aria-selected',String(on));b.tabIndex=on?0:-1;});document.querySelectorAll('.tab-content').forEach(panel=>{const on=panel.id==='tab-'+key;panel.classList.toggle('active',on);panel.hidden=!on;});if(!rendered.has(key)){if(key==='recap')renderRecap();else if(key==='insights')renderInsights();else renderPlatform(key);rendered.add(key);}}
buttons.forEach((b,i)=>{b.id='nav-'+b.dataset.tab;b.setAttribute('role','tab');b.setAttribute('aria-controls','tab-'+b.dataset.tab);document.getElementById('tab-'+b.dataset.tab).setAttribute('role','tabpanel');document.getElementById('tab-'+b.dataset.tab).setAttribute('aria-labelledby',b.id);b.addEventListener('click',()=>activate(b.dataset.tab));b.addEventListener('keydown',e=>{let j=i;if(e.key==='ArrowRight')j=(i+1)%buttons.length;else if(e.key==='ArrowLeft')j=(i+buttons.length-1)%buttons.length;else if(e.key==='Home')j=0;else if(e.key==='End')j=buttons.length-1;else return;e.preventDefault();buttons[j].focus();activate(buttons[j].dataset.tab);});});
document.getElementById('tabNav').setAttribute('role','tablist');
document.getElementById('heroMeta').innerHTML=Object.values(DATA.platforms).map(p=>'<span><b>'+esc(p.platform==='ios'?'iOS':'Android')+' '+esc(p.summary.version)+'</b>Build '+esc(p.summary.build)+' · '+esc(p.summary.date)+'</span>').join('');
activate(DATA.initial||'recap');
})();
'''
def standard_html(title,platforms,initial='recap',links=None):
 data={'schemaVersion':SCHEMA_VERSION,'title':title,'platforms':platforms,'initial':initial,'links':links or {}}
 serialized=json.dumps(data,ensure_ascii=False).replace('<',chr(92)+'u003c')
 return '<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+html.escape(title)+' — Report unificato</title><style>'+STYLE+'</style></head><body><header class="hero"><h1>'+html.escape(title)+' — Report unificato</h1><p>Dimensioni, componenti e verifiche di sicurezza per iOS e Android</p><div class="hero-meta" id="heroMeta"></div></header><nav class="tabs" id="tabNav" aria-label="Sezioni del report"><button data-tab="recap">Sintesi</button><button data-tab="ios">Analisi iOS</button><button data-tab="android">Analisi Android</button><button data-tab="insights">Insight</button></nav><main><div id="tab-recap" class="tab-content active"></div><div id="tab-ios" class="tab-content"></div><div id="tab-android" class="tab-content"></div><div id="tab-insights" class="tab-content"></div><footer class="note">Standard FRTMTools 1.2 · Esiti e priorità riferiti agli artefatti forniti · Sfruttabilità non confermata</footer></main><script>const DATA='+serialized+';</script><script>'+SCRIPT+'</script></body></html>'


def output_report(d,files,f,dependencies,stripping,folder):
 label=d['label'];p='android' if d['platform']=='Android' else 'ios'
 model=standard_platform(d,files,f,dependencies,stripping)
 (folder/(label+'-report.json')).write_text(json.dumps(model,ensure_ascii=False,indent=2))
 import csv
 with (folder/(label+'-duplicates.csv')).open('w',newline='') as stream:
  writer=csv.writer(stream);writer.writerow(['sha256','copies','bytes_each','redundant_bytes','paths'])
  for x in d['duplicates']:writer.writerow([x['sha256'],x['copies'],x['bytes_each'],x['redundant_bytes'],'; '.join(x['paths'])])
 links={p:{'pdf':label+'.pdf','json':label+'-report.json','csv':label+'-duplicates.csv','unified':'../report-unificato.html'}}
 (folder/(label+'.html')).write_text(standard_html(Path(d['input']).stem,{p:model},initial=p,links=links))
 return {'label':label,'title':Path(d['input']).name,'html':label+'.html','pdf':label+'.pdf','json':label+'-report.json'}

def archive_inventory(archive):
 groups=defaultdict(lambda:{'bytes':0,'compressed_bytes':0,'files':0})
 with zipfile.ZipFile(archive) as z:
  for entry in z.infolist():
   if entry.is_dir():continue
   group=entry.filename.split('/',1)[0];row=groups[group]
   row['bytes']+=entry.file_size;row['compressed_bytes']+=entry.compress_size;row['files']+=1
 checksum=hashlib.sha256()
 with archive.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1048576),b''):checksum.update(chunk)
 return {'package_bytes':archive.stat().st_size,'input_sha256':checksum.hexdigest(),'archive_contents':[{'group':key,**value} for key,value in sorted(groups.items())]}

def safe_extract(archive,destination):
 with zipfile.ZipFile(archive) as z:
  if sum(x.file_size for x in z.infolist())>8*1024**3:raise RuntimeError('Archive exceeds 8 GiB uncompressed limit')
  for entry in z.infolist():
   target=destination/entry.filename
   if not target.resolve().is_relative_to(destination.resolve()):raise RuntimeError('Unsafe archive path')
   if (entry.external_attr>>16)&0o170000==0o120000:raise RuntimeError('Archive symlinks are not supported')
  z.extractall(destination)

def candidates(source):
 if source.suffix.lower()=='.app':return [source]
 if source.is_file():return [source]
 paths=[]
 for root,dirs,files in os.walk(source):
  dirs[:]=[d for d in dirs if d!='Report-FRTMTools' and not d.startswith('.') and not (Path(root)/d).resolve().is_relative_to(OUT.parent)]
  apps=[Path(root)/d for d in dirs if d.endswith('.app')]
  paths.extend(apps);dirs[:]=[d for d in dirs if not d.endswith('.app')]
  paths.extend(Path(root)/f for f in files if Path(f).suffix.lower() in ('.apk','.ipa'))
 return sorted(paths)

if __name__=='__main__':
 source=Path(sys.argv[1]).resolve();folder=Path(sys.argv[2]).resolve();OFFLINE='--offline' in sys.argv[3:]
 app_map={}
 if '--app-map' in sys.argv[3:]:
  position=sys.argv.index('--app-map')
  if position+1>=len(sys.argv):raise SystemExit('Missing app map path')
  app_map=json.loads(Path(sys.argv[position+1]).read_text())
  if not isinstance(app_map,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in app_map.items()):raise SystemExit('App map must map identifiers to app names')
 folder.mkdir(parents=True,exist_ok=True);OUT=folder/'audit-evidence';OUT.mkdir(exist_ok=True)
 found=candidates(source)
 if not found:raise SystemExit('No .apk, .ipa or .app inputs found')
 results=[];failures=[];upstream_cache={}
 for index,p in enumerate(found):
  label=re.sub(r'[^A-Za-z0-9_-]+','-',p.stem).strip('-')+'-'+hashlib.sha256(str(p).encode()).hexdigest()[:8]
  try:
   with tempfile.TemporaryDirectory(prefix='frtm-audit-') as temporary:
    temporary=Path(temporary);app=p
    if p.suffix.lower() in ('.ipa','.zip'):
     safe_extract(p,temporary);apps=list(temporary.glob('Payload/*.app'))+list(temporary.glob('*.xcarchive/Products/Applications/*.app'))
     if len(apps)!=1:raise RuntimeError('Expected exactly one .app bundle in archive')
     app=apps[0]
    kind='Android' if p.suffix.lower()=='.apk' else 'iOS'
    if kind=='iOS' and app.suffix!='.app':raise RuntimeError('Supported inputs: .apk, .ipa, .app, .xcarchive.zip')
    print('Audit '+str(index+1)+'/'+str(len(found))+': '+p.name,flush=True)
    d=collect(kind,app,label);d['input']=str(p)
    if p.suffix.lower() in ('.ipa','.zip'):d.update(archive_inventory(p))
    files=json.loads((OUT/(label+'-files.json')).read_text());f=findings(d,files);stripping=[]
    if kind=='iOS':stripping=measure_strip(app)
    deps=dependency_audit(d,OFFLINE,upstream_cache);f.extend(advisory_findings(d,deps))
    (OUT/(label+'-findings.json')).write_text(json.dumps(f,indent=2));(OUT/(label+'-audit.json')).write_text(json.dumps(d,indent=2,default=str));(OUT/(label+'-dependencies.json')).write_text(json.dumps(deps,indent=2));(OUT/(label+'-strip.json')).write_text(json.dumps(stripping,indent=2))
    app_name=re.sub(r'[^A-Za-z0-9 ._-]+','-',p.stem)
    if kind=='iOS':app_name=d['info'].get('CFBundleDisplayName',app_name)
    else:app_name=d['manifest']['package']
    app_name=re.sub(r'[^A-Za-z0-9 ._-]+','-',app_name).strip('. ') or label
    identity=d['manifest']['package'] if kind=='Android' else d['info'].get('CFBundleIdentifier',app_name)
    app_name = re.sub(r'[^A-Za-z0-9 ._-]+','-',app_map.get(identity,identity)).strip('. ') or label
    report_folder=folder/app_name/('android' if kind=='Android' else 'ios');report_folder.mkdir(parents=True,exist_ok=True)
    report=output_report(d,files,f,deps,stripping,report_folder)
    for key in ['html','pdf','json']:report[key]=str((report_folder/report[key]).relative_to(folder))
    evidence=report_folder/'audit-evidence';evidence.mkdir(exist_ok=True)
    for artifact in list(OUT.glob(label+'-*')):shutil.move(str(artifact),evidence/artifact.name)
    results.append(report)
  except Exception as e:
   failures.append({'input':str(p),'error':str(e)});print('FAILED '+p.name+': '+str(e),file=sys.stderr,flush=True)
 grouped={}
 for report in results:
  model=json.loads((folder/report['json']).read_text());relative=Path(report['json']);app=relative.parts[0];platform=model['platform']
  group=grouped.setdefault(app,{'platforms':{},'links':{}});group['platforms'][platform]=model
  group['links'][platform]={'pdf':str(Path(report['pdf']).relative_to(app)),'json':str(relative.relative_to(app)),'csv':str(Path(report['html']).with_name(report['label']+'-duplicates.csv').relative_to(app))}
 for app,group in grouped.items():
  (folder/app/'report-unificato.html').write_text(standard_html(app,group['platforms'],links=group['links']))
 (folder/'audit-run.json').write_text(json.dumps({'reports':results,'failures':failures},indent=2))
 index=render_table(['App','HTML','PDF'],[[x['title'],x['html'],x['pdf']] for x in results])
 # Explicit local artifact links; upstream source listings stay in evidence JSON.
 index='<table><tr><th>App</th><th>HTML</th><th>PDF</th></tr>'+''.join('<tr><td>'+h(x['title'])+'</td><td><a href="'+x['html']+'">HTML</a></td><td><a href="'+x['pdf']+'">PDF</a></td></tr>' for x in results)+'</table>'
 (folder/'index-audit.html').write_text('<!doctype html><html lang="it"><head><meta charset="utf-8"><title>Audit</title><style>'+STYLE+'</style></head><body><main><h1>Audit applicazioni</h1>'+index+render_table(['Input non analizzato','Errore'],[[x['input'],x['error']] for x in failures])+'</main></body></html>')
 sys.exit(2 if failures else 0)

"""#
}
