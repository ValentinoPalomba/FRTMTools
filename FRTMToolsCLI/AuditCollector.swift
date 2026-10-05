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
SCHEMA_VERSION='1.3'
STANDARD_FIELDS=['summary','sizeBreakdown','categories','libraries','advisories','excludedAdvisories','assessment','duplicates','privacy','entitlements','hardening','buildQuality','connections','deadCode','permissions','components','dynamicModules','maintenance','actions']
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

STYLE=r'''[hidden]{display:none!important}
:root{color-scheme:light dark;--bg:#f4f6f8;--surface:#fff;--subtle:#f8fafc;--border:#e1e6ec;--text:#192b3d;--muted:#536577;--accent:#225e91;--accent-soft:#eaf2f9;--good:#16734c;--good-soft:#eaf5ef;--warn:#986015;--warn-soft:#fff4e2;--bad:#b33238;--bad-soft:#fcebed;--radius:10px;--space:24px}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}button,input,select{font:inherit}button,a,input,select,summary{touch-action:manipulation}a{color:var(--accent);text-underline-offset:3px}button{cursor:pointer}button:disabled{cursor:default;opacity:.45}button,a,input,select,summary,th{outline-offset:4px}:focus-visible{outline:2px solid var(--accent)}h1,h2,h3,p{margin:0}h1,h2,h3{text-wrap:balance}h1{font-size:28px;line-height:1.25;letter-spacing:-.025em;font-weight:650}h2{font-size:20px;line-height:1.4;letter-spacing:-.015em;font-weight:650}h3{font-size:14px;font-weight:650;line-height:1.45}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;overflow-wrap:anywhere}.muted,.small{color:var(--muted)}.small{font-size:12px}.brandbar{background:var(--surface);border-bottom:1px solid var(--border)}.brandbar-inner,.hero-inner,.tabs-inner,main{max-width:1480px;margin:auto;padding-left:40px;padding-right:40px}.brandbar-inner{min-height:52px;display:flex;justify-content:space-between;gap:16px;align-items:center}.brand{font-size:13px;font-weight:700;letter-spacing:.015em;display:flex;align-items:center;gap:10px}.brand-mark{display:grid;place-items:center;width:26px;height:26px;border-radius:6px;background:var(--accent);color:white;font-size:10px}.brand-context{font-size:12px;color:var(--muted)}.hero{background:var(--surface)}.hero-inner{padding-top:32px;padding-bottom:28px;display:flex;align-items:flex-start;justify-content:space-between;gap:24px}.hero p{font-size:13px;color:var(--muted);margin-top:8px}.hero-meta{display:flex;gap:16px;flex-wrap:wrap;align-items:center;margin-top:16px;font-size:12px;color:var(--muted)}.hero-meta span{display:flex;gap:8px;align-items:center}.hero-meta b{color:var(--text);font-weight:600}.hero-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:8px;padding-top:4px}.tabs{position:sticky;top:0;z-index:10;background:var(--surface);border-bottom:1px solid var(--border)}.tabs-inner{display:flex;gap:28px;overflow:auto}.tabs button{position:relative;border:0;border-bottom:3px solid transparent;padding:16px 0 13px;background:none;color:var(--muted);font-weight:600;font-size:13px;white-space:nowrap;min-height:48px}.tabs button:hover{color:var(--text)}.tabs button.active{color:var(--accent);border-bottom-color:var(--accent)}main{padding-top:32px;padding-bottom:32px}.tab-content{display:none}.tab-content.active{display:block}.page-heading,.section-heading{display:flex;justify-content:space-between;align-items:center;gap:16px;margin-bottom:20px}.page-heading p,.section-heading p{font-size:12px;color:var(--muted);margin-top:4px}.tab-section{margin-bottom:32px;scroll-margin-top:80px}.platform-line{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:16px}.platform-info{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.platform-tag{border:1px solid var(--border);border-radius:5px;background:var(--surface);padding:3px 10px;font-weight:650;font-size:12px}.platform-info .mono{color:var(--muted);font-size:11px}.platform-version{font-size:12px;color:var(--muted)}.metric-strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);margin-bottom:24px;overflow:hidden}.metric{padding:20px 22px;border-right:1px solid var(--border)}.metric:last-child{border:0}.metric-label{font-size:12px;color:var(--muted);font-weight:500;display:block}.metric-value{display:block;font-size:27px;line-height:1.3;font-weight:650;letter-spacing:-.025em;font-variant-numeric:tabular-nums;margin:7px 0 5px}.metric-value .unit{font-size:13px;letter-spacing:0;font-weight:500;color:var(--muted);margin-left:4px}.metric-sub{display:block;font-size:11px;color:var(--muted)}.grid{display:grid;gap:20px}.grid-2{grid-template-columns:repeat(2,minmax(0,1fr))}.chart-pair{grid-template-columns:minmax(0,1.35fr) minmax(0,1fr)}.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:24px;min-width:0}.card>h3{margin-bottom:20px}.chart-note{color:var(--muted);font-size:11px;margin-top:16px}.chart-empty{min-height:140px;display:grid;place-items:center;color:var(--muted);font-size:12px}.bar-row{display:grid;grid-template-columns:minmax(110px,1fr) minmax(80px,1.7fr) 90px;align-items:center;gap:14px;margin:15px 0;font-size:12px}.bar-row>span{overflow-wrap:anywhere}.bar-row b{text-align:right;font-size:12px;font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap}.stat-bar{height:9px;background:var(--subtle);border-radius:3px;overflow:hidden}.stat-bar span{height:100%;display:block;border-radius:3px}.donut-chart{display:grid;grid-template-columns:180px minmax(0,1fr);align-items:center;gap:24px;min-height:220px}.donut-chart svg{width:180px;display:block}.legend-row{display:grid;grid-template-columns:8px minmax(0,1fr) auto;gap:9px;align-items:center;margin:11px 0;font-size:11px}.legend-row .dot{width:8px;height:8px;border-radius:2px}.legend-row b{font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap}.legend-row small{grid-column:2/4;color:var(--muted);font-size:10px;margin-top:-5px}.jump-nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:24px}.chip-btn,.button{display:inline-flex;align-items:center;justify-content:center;gap:6px;min-height:36px;padding:7px 13px;border:1px solid var(--border);border-radius:6px;background:var(--surface);color:var(--text);text-decoration:none;font-size:12px;font-weight:550;transition:background .16s,border-color .16s}.chip-btn:hover,.button:hover{background:var(--subtle);border-color:var(--muted)}.chip-btn.active,.button.primary{color:var(--accent);background:var(--accent-soft);border-color:var(--accent)}.button.primary:hover{background:var(--surface)}.badge{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:600;padding:3px 8px;border-radius:5px;white-space:nowrap}.badge::before{content:'';width:5px;height:5px;background:currentColor;border-radius:50%}.badge-PASS{color:var(--good);background:var(--good-soft)}.badge-WARN,.badge-Medium{color:var(--warn);background:var(--warn-soft)}.badge-FAIL,.badge-High{color:var(--bad);background:var(--bad-soft)}.badge-Low,.badge-NA,.badge-unknown{color:var(--muted);background:var(--subtle)}.table-panel{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden}.table-note{padding:16px 20px 0;color:var(--muted);font-size:12px}.table-toolbar{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;padding:16px 20px}.search-wrap{flex:1;max-width:340px;min-width:180px}.table-toolbar input{width:100%;border:1px solid var(--border);border-radius:6px;padding:8px 12px;background:var(--surface);color:var(--text);font-size:12px;min-height:36px}.table-toolbar input::placeholder{color:var(--muted)}.table-toolbar select,.table-footer select{padding:7px 10px;border:1px solid var(--border);border-radius:5px;background:var(--surface);color:var(--text);font-size:12px;min-height:36px}.table-toolbar label,.table-footer label{color:var(--muted);font-size:11px}.count{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}.accordion-tabs{display:flex;flex-wrap:wrap;gap:8px;padding:0 20px 16px}.table-scroll{overflow:auto;max-height:740px}table{width:100%;border-collapse:collapse;text-align:left;font-size:12px}th{position:sticky;top:0;z-index:1;background:var(--subtle);color:var(--muted);font-size:11px;font-weight:650;padding:12px 16px;border-top:1px solid var(--border);border-bottom:1px solid var(--border);white-space:nowrap;cursor:pointer}th::after{content:' ↕';color:var(--muted);opacity:.5}th[aria-sort=ascending]::after{content:' ↑';opacity:1}th[aria-sort=descending]::after{content:' ↓';opacity:1}td{padding:13px 16px;border-bottom:1px solid var(--border);vertical-align:top;overflow-wrap:anywhere;min-width:80px;max-width:380px}tbody tr:last-child td{border-bottom:0}tbody tr:hover{background:var(--subtle)}td.numeric{text-align:right;font-variant-numeric:tabular-nums;min-width:110px}td.numeric b{font-weight:550;white-space:nowrap}.cell-sub{display:block;font-size:10px;color:var(--muted);margin-top:3px}.cell-path{display:block;font-size:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;line-height:1.55;overflow-wrap:anywhere}.cell-details{margin-top:7px}.cell-details summary{font-size:11px;color:var(--accent);cursor:pointer}.cell-details[open] summary{margin-bottom:8px}.cell-details dl,.finding-body dl{margin:0}.cell-details dt{font-size:10px;color:var(--muted);margin-top:10px}.cell-details dd{margin:2px 0 0;font-size:11px;overflow-wrap:anywhere}.table-footer{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;padding:12px 20px;border-top:1px solid var(--border);font-size:11px;color:var(--muted)}.pager{display:flex;align-items:center;gap:8px}.pager button{border:1px solid var(--border);border-radius:5px;padding:5px 10px;min-height:32px;background:var(--surface);color:var(--text);font-size:11px}.empty-state{text-align:center;padding:40px;color:var(--muted)}.finding-list{border-top:1px solid var(--border)}.finding{border-bottom:1px solid var(--border);background:var(--surface)}.finding:last-child{border-bottom:0}.finding>summary{cursor:pointer;list-style:none;display:grid;grid-template-columns:90px minmax(0,1fr) 20px;align-items:start;gap:14px;padding:20px}.finding>summary::-webkit-details-marker{display:none}.finding>summary::after{content:'+';font-size:18px;color:var(--muted);text-align:center;line-height:1.2}.finding[open]>summary::after{content:'−'}.finding>summary:hover{background:var(--subtle)}.finding-id{display:block;color:var(--muted);font-size:10px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;margin-bottom:4px}.finding-title{font-weight:600;display:block;font-size:13px}.finding-meta{display:block;font-size:11px;color:var(--muted);margin-top:5px}.finding-body{padding:0 20px 22px 124px}.finding-body .evidence-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.finding-body dt{font-size:11px;color:var(--muted);margin-bottom:6px}.finding-body dd{margin:0 0 16px;font-size:12px;overflow-wrap:anywhere;max-width:75ch}.finding-body .evidence{font-size:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;line-height:1.7}.checklist .item{padding:14px 0;border-bottom:1px solid var(--border)}.checklist .item:first-child{padding-top:0}.checklist .item:last-child{padding-bottom:0;border-bottom:0}.checklist .head{display:flex;justify-content:space-between;gap:12px;font-size:12px;font-weight:550}.checklist .detail{font-size:11px;color:var(--muted);margin-top:5px;overflow-wrap:anywhere}.disclosure{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius)}.disclosure>summary{cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:16px;padding:18px 20px;font-weight:600;font-size:13px;list-style:none}.disclosure>summary::-webkit-details-marker{display:none}.disclosure>summary::after{content:'+';color:var(--muted);font-size:18px}.disclosure[open]>summary::after{content:'−'}.disclosure>.table-panel{border:0;border-radius:0}.section-description{font-size:12px;color:var(--muted);margin-top:5px;max-width:75ch}.download-panel{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:20px 24px;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius)}.download-panel .jump-nav{margin:0}.report-footer{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;border-top:1px solid var(--border);padding-top:20px;font-size:11px;color:var(--muted)}.skip-link{position:absolute;left:16px;top:-60px;z-index:20;background:var(--surface);padding:12px;border:2px solid var(--accent)}.skip-link:focus{top:12px}.tab-content[hidden]{display:none!important}
@media(prefers-color-scheme:dark){:root{--bg:#101820;--surface:#17222d;--subtle:#1d2c39;--border:#304252;--text:#e3edf5;--muted:#afc0d0;--accent:#91bde3;--accent-soft:#203e56;--good:#88d1ad;--good-soft:#173b2c;--warn:#edc37e;--warn-soft:#3d301b;--bad:#f3a3a8;--bad-soft:#46242a}.brand-mark{background:#306692;color:#fff}}
@media(max-width:1100px){.brandbar-inner,.hero-inner,.tabs-inner,main{padding-left:24px;padding-right:24px}.donut-chart{grid-template-columns:145px minmax(0,1fr);gap:16px}.donut-chart svg{width:145px}.metric{padding:18px}.chart-pair{grid-template-columns:repeat(2,minmax(0,1fr))}.bar-row{grid-template-columns:110px minmax(60px,1fr) 75px;gap:10px}}
@media(max-width:760px){.brandbar-inner,.hero-inner,.tabs-inner,main{padding-left:16px;padding-right:16px}.brand-context{display:none}.hero-inner{flex-direction:column;padding-top:24px;padding-bottom:20px;gap:12px}h1{font-size:23px}.hero-actions{justify-content:flex-start}.tabs-inner{gap:24px}.grid-2,.chart-pair{grid-template-columns:1fr}.metric-strip{grid-template-columns:repeat(2,minmax(0,1fr))}.metric{border-bottom:1px solid var(--border)}.metric:nth-child(even){border-right:0}.metric-value{font-size:25px}.metric-strip .metric:last-child{border-bottom:0}.card{padding:20px}.page-heading,.platform-line{align-items:flex-start}.platform-line{flex-direction:column}.donut-chart{grid-template-columns:145px minmax(0,1fr)}.finding>summary{grid-template-columns:70px minmax(0,1fr) 16px;gap:12px;padding:16px}.finding-body{padding:0 16px 20px}.finding-body .evidence-grid{grid-template-columns:1fr;gap:0}.table-scroll table{min-width:650px}.table-toolbar{padding:16px}.table-footer{padding:12px 16px}.accordion-tabs{padding:0 16px 16px}.download-panel{flex-direction:column;align-items:flex-start;padding:20px}.chip-btn,.button,.pager button,.table-toolbar select,.table-footer select{min-height:44px}.report-footer{font-size:10px}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
@media print{body{background:white;color:#192b3d}.brandbar,.tabs,.hero-actions,.jump-nav,.table-toolbar,.table-footer,.accordion-tabs,.skip-link{display:none!important}.hero-inner,main{max-width:none;padding:12px 0}.tab-content,.tab-content[hidden]{display:block!important}.tab-section{margin-bottom:24px}.card,.table-panel{box-shadow:none;border-color:#ddd;break-inside:avoid}.metric-strip{grid-template-columns:repeat(5,1fr)}.metric{padding:12px}.metric-value{font-size:21px}.table-scroll{max-height:none;overflow:visible}.table-scroll table{min-width:0}.grid-2,.chart-pair{grid-template-columns:repeat(2,minmax(0,1fr))}th{position:static}.finding{break-inside:avoid}}
'''
SCRIPT=r'''(function(){
'use strict';
const esc=x=>String(x??'—').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=x=>new Intl.NumberFormat('it-IT',{maximumFractionDigits:2}).format(x||0);
const mib=x=>num(x/1048576)+' MiB';
const size=x=>x===null||x===undefined?'—':x>=1048576?mib(x):x>=1024?num(x/1024)+' KiB':num(x)+' B';
const metricSize=x=>x===null||x===undefined?'—':num(x/1048576)+'<span class="unit">MiB</span>';
const safeUrl=x=>typeof x==='string'&&/^https:\/\/[^\s]+$/.test(x);
const val=x=>x===null||x===undefined?'—':typeof x==='boolean'?(x?'Sì':'No'):typeof x==='number'?num(x):safeUrl(x)?'<a href="'+esc(x)+'" target="_blank" rel="noopener noreferrer">Apri advisory ↗</a>':esc(x);
const names={PASS:'Superato',WARN:'Da approfondire',FAIL:'Non superato',NA:'Non applicabile',UNKNOWN:'Non disponibile'};
const severityNames={critical:'Critica',high:'Alta',moderate:'Media',medium:'Media',low:'Bassa',unknown:'Da verificare'};
const priorityOrder={'Critica':0,'Alta':1,'Media':2,'Bassa':3,'Da verificare':4};
const palette=['#356f9d','#598b85','#a88342','#7589ab','#a0b3c1','#697f70','#a77879','#7e7998'];
const categoryColors={'Componenti software':palette[0],'Librerie native':palette[0],'Asset Flutter':palette[1],'Risorse Android':palette[2],'Altre risorse':palette[3],'Codice principale':palette[4],'Codice Android':palette[4],'Codice app Flutter AOT':palette[5]};
const semanticColor=(x,i)=>({'Critica':'#8b2834','Alta':'#b3434a','Media':'#b38338','Bassa':'#4f8296','Da verificare':'#7e8e9b','Superato':'#43836a','Da approfondire':'#b38338','Non superato':'#b3434a','Non applicabile':'#7e8e9b','Non disponibile':'#7e8e9b'}[x.name]||categoryColors[x.name]||palette[i%palette.length]);
function badge(value){const label=names[value]||severityNames[String(value).toLowerCase()]||value;const key=names[value]?value:{Critica:'High',Alta:'High',Media:'Medium',Bassa:'Low'}[label]||'unknown';return '<span class="badge badge-'+key+'">'+esc(label)+'</span>';}
const platformName=p=>p==='ios'?'iOS':'Android';
let counter=0,printing=false;const pending=[];
function blockFor(p,key){return (p.blocks||[]).find(b=>b.key===key);}
function heading(title,description='',aside=''){return '<div class="section-heading"><div><h2>'+esc(title)+'</h2>'+(description?'<p>'+esc(description)+'</p>':'')+'</div>'+aside+'</div>';}
function metric(label,value,sub=''){return '<div class="metric"><span class="metric-label">'+esc(label)+'</span><strong class="metric-value">'+value+'</strong><span class="metric-sub">'+esc(sub)+'</span></div>';}
function metrics(p){const s=p.summary;return '<div class="metric-strip">'+(s.packageBytes!==undefined?metric('Pacchetto',metricSize(s.packageBytes),'Artefatto compresso'):'')+metric('Bundle analizzato',metricSize(s.contentBytes),num(s.files)+' file')+metric('Segnalazioni statiche',num(s.findings),num(s.advisories||0)+' advisory candidati inclusi')+metric('Componenti',num(s.libraries),'Inventario incluso nel pacchetto')+metric('Duplicati ridondanti',metricSize(s.duplicateBytes),num(s.duplicateGroups)+' gruppi con copie identiche')+'</div>';}
function table(block){if(!block)return '';const id='data-table-'+(++counter);pending.push([id,block]);return '<div id="'+id+'"></div>';}
function section(p,key,collapsed=false){const b=blockFor(p,key);if(!b||key==='localization')return '';const panel='<div class="table-panel">'+(b.note?'<p class="table-note">'+esc(b.note)+'</p>':'')+table(b)+'</div>';const aside='<span class="count">'+num(b.rows.length)+' voci</span>';return '<section class="tab-section" id="'+p.platform+'-'+key+'">'+(collapsed?'<details class="disclosure"><summary><span>'+esc(b.title)+'</span>'+aside+'</summary>'+panel+'</details>':heading(b.title,'',aside)+panel)+'</section>';}
function sourceValue(block,row,name){const i=block.headers.indexOf(name);return i<0?null:row[i];}
function findingsTable(container,block){
 let query='',selected='Tutte',order='priority';const rows=block.rows||[];
 container.innerHTML='<div class="table-toolbar"><div class="search-wrap"><input type="search" placeholder="Cerca segnalazioni o evidenze…" aria-label="Cerca segnalazioni"></div><label>Ordina <select aria-label="Ordina segnalazioni"><option value="priority">Priorità</option><option value="id">Identificativo</option></select></label><span class="count" aria-live="polite"></span></div><div class="accordion-tabs">'+['Tutte','Alta','Media','Bassa','Da verificare'].map(x=>'<button class="chip-btn '+(x==='Tutte'?'active':'')+'" data-severity="'+x+'" aria-pressed="'+(x==='Tutte')+'">'+x+'</button>').join('')+'</div><div class="finding-list"></div>';
 const render=()=>{
  const filtered=rows.filter(row=>printing||(row.some(x=>String(x??'').toLowerCase().includes(query))&&(selected==='Tutte'||sourceValue(block,row,'Priorità')===selected))).slice();
  filtered.sort((a,b)=>order==='id'?String(sourceValue(block,a,'ID')).localeCompare(String(sourceValue(block,b,'ID'))):(priorityOrder[sourceValue(block,a,'Priorità')]??4)-(priorityOrder[sourceValue(block,b,'Priorità')]??4));
  container.querySelector('.count').textContent=num(filtered.length)+' / '+num(rows.length)+' segnalazioni';
  container.querySelector('.finding-list').innerHTML=filtered.length?filtered.map(row=>'<details class="finding"><summary>'+badge(sourceValue(block,row,'Priorità'))+'<span><span class="finding-id">'+esc(sourceValue(block,row,'ID'))+'</span><span class="finding-title">'+esc(sourceValue(block,row,'Tema'))+'</span><span class="finding-meta">'+esc(sourceValue(block,row,'Area'))+' · '+esc(sourceValue(block,row,'CWE')||'CWE non attribuita')+'</span></span></summary><div class="finding-body"><div class="evidence-grid"><dl><dt>Stato del riscontro</dt><dd>'+esc(sourceValue(block,row,'Stato'))+'</dd><dt>Evidenza osservata</dt><dd class="evidence">'+esc(sourceValue(block,row,'Evidenza'))+'</dd></dl><dl><dt>Intervento</dt><dd>'+esc(sourceValue(block,row,'Intervento'))+'</dd></dl></div></div></details>').join(''):'<div class="empty-state">'+(rows.length?'Nessuna segnalazione corrisponde ai filtri.':'Nessuna segnalazione registrata per i controlli eseguiti.')+'</div>';
 };
 container.querySelector('input').addEventListener('input',e=>{query=e.target.value.toLowerCase();render();});
 container.querySelector('select').addEventListener('change',e=>{order=e.target.value;render();});
 container.querySelectorAll('[data-severity]').forEach(button=>button.addEventListener('click',()=>{selected=button.dataset.severity;container.querySelectorAll('[data-severity]').forEach(x=>{x.classList.toggle('active',x===button);x.setAttribute('aria-pressed',String(x===button));});render();}));window.addEventListener('audit-print',render);render();
}
function cell(value,header){
 if(value===null||value===undefined)return '—';
 if(typeof value==='number'&&/byte/i.test(header))return '<b>'+size(value)+'</b><span class="cell-sub">'+num(value)+' byte</span>';
 if(['Esito','Stato verifica','Priorità','Gravità'].includes(header))return badge(value);
 if((header==='File'||header==='Binario'||header==='Componente'||header==='Libreria o gruppo')&&typeof value==='string'&&value.includes('/')){const name=value.split('/').pop();return '<span>'+esc(name)+'</span><span class="cell-sub mono">'+esc(value)+'</span>';}
 if(header==='Percorsi'&&typeof value==='string'){const paths=value.split('; ');return paths.slice(0,2).map(x=>'<span class="cell-path">'+esc(x)+'</span>').join('')+(paths.length>2?'<details class="cell-details"><summary>Altri '+num(paths.length-2)+' percorsi</summary>'+paths.slice(2).map(x=>'<span class="cell-path">'+esc(x)+'</span>').join('')+'</details>':'');}
 if(/Versione|Release|stabile|^ID$|CWE|Identificativo/i.test(header))return '<span class="mono">'+val(value)+'</span>';
 return val(value);
}
function advisoryCells(block,row){
 const get=name=>sourceValue(block,row,name);const included=get('Versione inclusa'),matched=get('Versione confrontata');const url=get('Link');
 const id=safeUrl(url)?'<a class="mono" href="'+esc(url)+'" target="_blank" rel="noopener noreferrer">'+esc(get('Avviso'))+' ↗</a>':'<span class="mono">'+esc(get('Avviso'))+'</span>';
 return ['<strong>'+esc(get('Libreria'))+'</strong>','<span class="mono">'+esc(included)+'</span>'+(matched&&matched!==included?'<span class="cell-sub mono">Upstream '+esc(matched)+'</span>':''),id+(get('CVE')&&get('CVE')!==get('Avviso')?'<span class="cell-sub mono">'+esc(get('CVE'))+'</span>':''),badge(get('Gravità')||'unknown'),'<span class="mono">'+esc(get('Intervallo interessato'))+'</span>'+(get('Correzione indicata')?'<span class="cell-sub">Correzione: '+esc(get('Correzione indicata'))+'</span>':''),'<details class="cell-details"><summary>Dettagli</summary><dl>'+block.headers.map((h,i)=>'<dt>'+esc(h)+'</dt><dd>'+val(row[i])+'</dd>').join('')+'</dl></details>'];
}
function buildTable(container,block){
 if(block.key==='assessment'){findingsTable(container,block);return;}
 let query='',sort=-1,dir=1,page=0,pageSize=25;const data=block.rows||[],compact=block.key==='advisories';const headers=compact?['Componente','Versione','Advisory / CVE','Gravità','Range / correzione','Evidenze']:block.headers;
 container.innerHTML='<div class="table-toolbar"><div class="search-wrap"><input type="search" placeholder="Cerca nella tabella…" aria-label="Cerca in '+esc(block.title)+'"></div><span class="count" aria-live="polite"></span></div><div class="table-scroll" tabindex="0" role="region" aria-label="'+esc(block.title)+'"><table><thead><tr>'+headers.map((h,i)=>'<th scope="col" tabindex="0" data-index="'+i+'">'+esc(h)+'</th>').join('')+'</tr></thead><tbody></tbody></table></div><div class="table-footer"><label>Righe <select aria-label="Righe per pagina"><option>25</option><option>50</option><option>100</option></select></label><span class="range"></span><div class="pager"><button data-page="previous" aria-label="Pagina precedente">← Precedente</button><button data-page="next" aria-label="Pagina successiva">Successiva →</button></div></div>';
 const sortValue=(row,index)=>compact?sourceValue(block,row,['Libreria','Versione inclusa','Avviso','Gravità','Intervallo interessato','Stato e limiti'][index]):row[index];
 const render=()=>{
  const rows=data.filter(row=>printing||row.some(x=>String(x??'').toLowerCase().includes(query))).slice();
  if(sort>=0)rows.sort((a,b)=>{const x=sortValue(a,sort),y=sortValue(b,sort);return dir*(typeof x==='number'&&typeof y==='number'?x-y:String(x??'').localeCompare(String(y??''),'it',{numeric:true}));});
  const pages=Math.max(1,Math.ceil(rows.length/pageSize));page=Math.min(page,pages-1);const start=page*pageSize,slice=printing?rows:rows.slice(start,start+pageSize);
  container.querySelector('tbody').innerHTML=slice.length?slice.map(row=>'<tr>'+(compact?advisoryCells(block,row).map(x=>'<td>'+x+'</td>').join(''):row.map((x,i)=>'<td'+(typeof x==='number'?' class="numeric"':'')+'>'+cell(x,headers[i])+'</td>').join(''))+'</tr>').join(''):'<tr><td colspan="'+headers.length+'" class="empty-state">'+(data.length?'Nessun risultato. Modifica la ricerca.':'Nessun record disponibile.')+'</td></tr>';
  container.querySelector('.count').textContent=num(rows.length)+(query?' / '+num(data.length):'')+' voci';
  const footer=container.querySelector('.table-footer');footer.hidden=rows.length<=25&&data.length<=25;
  container.querySelector('.range').textContent=rows.length?num(start+1)+'–'+num(Math.min(start+pageSize,rows.length))+' di '+num(rows.length):'0 voci';
  container.querySelector('[data-page="previous"]').disabled=page===0;container.querySelector('[data-page="next"]').disabled=page>=pages-1;
 };
 container.querySelector('input').addEventListener('input',e=>{query=e.target.value.toLowerCase();page=0;render();});
 container.querySelector('select').addEventListener('change',e=>{pageSize=Number(e.target.value);page=0;render();});
 container.querySelectorAll('[data-page]').forEach(button=>button.addEventListener('click',()=>{page+=button.dataset.page==='next'?1:-1;render();container.querySelector('.table-scroll').scrollTop=0;}));
 container.querySelectorAll('th').forEach(th=>{const change=()=>{const index=Number(th.dataset.index);dir=sort===index?-dir:1;sort=index;page=0;container.querySelectorAll('th').forEach(x=>x.removeAttribute('aria-sort'));th.setAttribute('aria-sort',dir===1?'ascending':'descending');render();};th.addEventListener('click',change);th.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();change();}});});window.addEventListener('audit-print',render);render();
}
function flush(){while(pending.length){const [id,block]=pending.shift();const node=document.getElementById(id);if(node)buildTable(node,block);}}
function bar(title,data,unit='voci'){
 const max=Math.max(...data.map(x=>x.value),1);return '<div class="card"><h3>'+esc(title)+'</h3><div class="bar-chart" role="img" aria-label="'+esc(data.map(x=>x.name+': '+num(x.value)+' '+unit).join('; '))+'">'+data.map((x,i)=>'<div class="bar-row"><span>'+esc(x.name)+'</span><div class="stat-bar"><span style="width:'+Math.max(0,x.value)/max*100+'%;background:'+semanticColor(x,i)+'"></span></div><b>'+num(x.value)+' '+esc(unit)+'</b></div>').join('')+'</div></div>';
}
function donut(title,data,unit='voci'){
 const total=data.reduce((sum,x)=>sum+x.value,0),circumference=2*Math.PI*72;let offset=0;
 const slices=data.filter(x=>x.value>0).map(x=>{const i=data.indexOf(x),length=x.value/total*circumference;const result='<circle cx="110" cy="110" r="72" fill="none" stroke="'+semanticColor(x,i)+'" stroke-width="22" stroke-dasharray="'+length+' '+(circumference-length)+'" stroke-dashoffset="'+(-offset)+'" transform="rotate(-90 110 110)"/>';offset+=length;return result;}).join('');
 return '<div class="card"><h3>'+esc(title)+'</h3><div class="donut-chart"><svg viewBox="0 0 220 220" role="img" aria-label="'+esc(data.map(x=>x.name+': '+num(x.value)+' '+unit).join('; '))+'"><circle cx="110" cy="110" r="72" fill="none" stroke="var(--border)" stroke-width="22"/>'+slices+'<text x="110" y="107" text-anchor="middle" fill="var(--text)" font-size="25" font-weight="600">'+num(total)+'</text><text x="110" y="129" text-anchor="middle" fill="var(--muted)" font-size="11">'+esc(unit)+'</text></svg><div>'+data.map((x,i)=>'<div class="legend-row"><span class="dot" style="background:'+semanticColor(x,i)+'"></span><span>'+esc(x.name)+'</span><b>'+num(x.value)+'</b><small>'+num(total?x.value/total*100:0)+'%</small></div>').join('')+'</div></div>'+(!total?'<p class="chart-note">Nessuna voce registrata.</p>':'')+'</div>';
}
function categories(p){return p.charts.categories.filter(x=>x.bytes>0).map(x=>({name:x.name,value:x.bytes/1048576}));}
function platformLine(p){const s=p.summary;return '<div class="platform-line"><div class="platform-info"><span class="platform-tag">'+platformName(p.platform)+'</span><span class="mono">'+esc(s.identifier)+'</span></div><span class="platform-version">Versione '+esc(s.version)+' · Build '+esc(s.build)+'</span></div>';}
function downloads(key){const links=DATA.links[key]||{};return '<section class="tab-section"><div class="download-panel"><div><h3>Report e dati</h3><p class="small">'+platformName(key)+' · Report completo e inventario</p></div><div class="jump-nav">'+[['pdf','Scarica PDF'],['json','Dati JSON'],['csv','Duplicati CSV'],['unified','Report unificato']].filter(([k])=>links[k]).map(([k,label])=>'<a class="button '+(k==='pdf'?'primary':'')+'" href="'+esc(links[k])+'"'+(k==='pdf'?' download':'')+'>'+label+'</a>').join('')+'</div></div></section>';}
function renderRecap(){
 const platforms=Object.values(DATA.platforms);let body=heading('Panoramica','Dimensioni, componenti e segnalazioni degli artefatti analizzati.');
 platforms.forEach(p=>{const s=p.summary;body+='<section class="tab-section">'+platformLine(p)+metrics(p)+'<div class="grid chart-pair">'+bar('Peso per categoria',categories(p),'MiB')+donut('Controlli della build',Object.entries(s.checks).filter(([,value])=>value>0).map(([name,value])=>({name:names[name]||name,value})))+'</div></section><section class="tab-section"><div class="grid grid-2">'+donut('Composizione del bundle',categories(p),'MiB')+bar('Segnalazioni per priorità',p.charts.severity.map(x=>({name:x.name,value:x.count})))+'</div></section>';});
 if(platforms.length>1)body+='<section class="tab-section">'+heading('Confronto tra piattaforme')+'<div class="grid grid-2">'+bar('Dimensioni analizzate',platforms.map(p=>({name:platformName(p.platform)+(p.summary.packageBytes!==undefined?' · pacchetto':' · bundle'),value:(p.summary.packageBytes??p.summary.contentBytes)/1048576})),'MiB')+bar('Segnalazioni statiche',platforms.map(p=>({name:platformName(p.platform),value:p.summary.findings})))+'</div></section>';
 platforms.forEach(p=>{body+=section({...p,platform:'overview-'+p.platform},'assessment');});
 document.getElementById('tab-recap').innerHTML=body;flush();
}
function libraryStates(block){const counts={};(block?.rows||[]).forEach(row=>{const raw=String(sourceValue(block,row,'Stato')||'');const name=/aggiornamento disponibile/i.test(raw)?'Aggiornamento disponibile':/allineata/i.test(raw)?'Allineate':/placeholder|da confermare/i.test(raw)?'Versione da verificare':'Versione identificata';counts[name]=(counts[name]||0)+1;});return Object.entries(counts).map(([name,value])=>({name,value}));}
function checklist(title,items){return '<div class="card"><h3>'+esc(title)+'</h3><div class="checklist">'+items.map(x=>'<div class="item"><div class="head"><span>'+esc(x.check)+'</span>'+badge(x.status)+'</div><div class="detail">'+val(x.value)+'</div></div>').join('')+'</div></div>';}
function renderPlatform(key){
 const p=DATA.platforms[key];if(!p)return;const s=p.summary;let body=heading('Analisi '+platformName(key),s.identifier)+metrics(p);
 body+='<div class="jump-nav">'+[['assessment','Segnalazioni'],['advisories','Advisory'],['sizeBreakdown','Dimensioni'],['libraries','Componenti'],['buildQuality','Configurazione'],['privacy','Privacy']].filter(([id])=>blockFor(p,id)).map(([id,label])=>'<a class="chip-btn" href="#'+key+'-'+id+'">'+label+'</a>').join('')+'</div>';
 body+=section(p,'assessment')+section(p,'advisories')+section(p,'excludedAdvisories',true)+section(p,'cwe',true);
 body+='<section class="tab-section">'+heading('Distribuzione delle segnalazioni')+'<div class="grid grid-2">'+bar('Priorità',p.charts.severity.map(x=>({name:x.name,value:x.count})))+bar('Aree interessate',p.charts.areas.filter(x=>x.count).map(x=>({name:x.name,value:x.count})))+'</div><p class="section-description">Una segnalazione può interessare più aree.</p></section>';
 body+='<section class="tab-section" id="'+key+'-sizeBreakdown">'+heading('Dimensioni e composizione','Valori del bundle analizzato, separati dal pacchetto compresso.')+'<div class="grid chart-pair">'+bar('Peso per categoria',categories(p),'MiB')+donut('Composizione del bundle',categories(p),'MiB')+'</div></section>'+section(p,'archiveContents')+section(p,'categories',true)+section(p,'duplicates');
 const libraries=blockFor(p,'libraries');if(libraries){body+='<section class="tab-section" id="'+key+'-libraries">'+heading('Componenti e framework','Inventario delle versioni incluse.', '<span class="count">'+num(libraries.rows.length)+' componenti</span>')+'<div class="grid grid-2">'+bar('Identificazione delle versioni',libraryStates(libraries))+donut('Stato delle versioni',libraryStates(libraries))+'</div><div style="margin-top:20px" class="table-panel">'+table(libraries)+'</div></section>';}
 body+='<section class="tab-section" id="'+key+'-buildQuality">'+heading('Configurazione e protezioni')+'<div class="grid grid-2">'+checklist('Configurazione della build',p.checks.filter(x=>x.group==='build'))+checklist('Indicatori del binario',p.checks.filter(x=>x.group==='hardening'))+'</div></section>';
 body+=section(p,'hardening',true)+section(p,'connections')+section(p,'codeIndicators',true);
 body+=key==='ios'?section(p,'privacy',true)+section(p,'entitlements',true)+section(p,'permissions',true)+section(p,'stripping',true):section(p,'permissions')+section(p,'components')+section(p,'dynamicModules');
 body+=section(p,'maintenance')+section(p,'actions')+downloads(key);document.getElementById('tab-'+key).innerHTML=body;flush();
}
function renderInsights(){
 const platforms=Object.values(DATA.platforms);const rows=platforms.map(p=>[platformName(p.platform),p.summary.files,p.summary.libraries,p.summary.findings,p.summary.duplicateBytes]);
 const overview={key:'insights',title:'Indicatori per piattaforma',headers:['Piattaforma','File','Componenti','Segnalazioni','Byte duplicati'],rows};
 const actions={key:'actions',title:'Interventi',headers:['Piattaforma','Azione','Chi coinvolgere','Risultato'],rows:platforms.flatMap(p=>(blockFor(p,'actions')?.rows||[]).map(row=>[platformName(p.platform),...row]))};
 let body=heading('Insight e interventi','Riepilogo dei dati e delle azioni associate ai riscontri.')+'<section class="tab-section"><div class="grid grid-2">'+bar('Duplicati ridondanti',platforms.map(p=>({name:platformName(p.platform),value:p.summary.duplicateBytes/1048576})),'MiB')+bar('Segnalazioni statiche',platforms.map(p=>({name:platformName(p.platform),value:p.summary.findings})))+'</div></section><section class="tab-section">'+heading(overview.title)+'<div class="table-panel">'+table(overview)+'</div></section><section class="tab-section">'+heading('Interventi')+'<div class="table-panel">'+table(actions)+'</div></section>';
 document.getElementById('tab-insights').innerHTML=body;flush();
}
document.querySelectorAll('#tabNav button').forEach(b=>{if(['ios','android'].includes(b.dataset.tab)&&!DATA.platforms[b.dataset.tab]){b.remove();document.getElementById('tab-'+b.dataset.tab).remove();}});
const rendered=new Set(),buttons=[...document.querySelectorAll('#tabNav button')];
function activate(key){if(!buttons.some(b=>b.dataset.tab===key))key='recap';buttons.forEach(b=>{const on=b.dataset.tab===key;b.classList.toggle('active',on);b.setAttribute('aria-selected',String(on));b.tabIndex=on?0:-1;});document.querySelectorAll('.tab-content').forEach(panel=>{const on=panel.id==='tab-'+key;panel.classList.toggle('active',on);panel.hidden=!on;});if(!rendered.has(key)){if(key==='recap')renderRecap();else if(key==='insights')renderInsights();else renderPlatform(key);rendered.add(key);}return key;}
buttons.forEach((button,i)=>{button.id='nav-'+button.dataset.tab;button.setAttribute('role','tab');button.setAttribute('aria-controls','tab-'+button.dataset.tab);const panel=document.getElementById('tab-'+button.dataset.tab);panel.setAttribute('role','tabpanel');panel.setAttribute('aria-labelledby',button.id);button.addEventListener('click',()=>activate(button.dataset.tab));button.addEventListener('keydown',event=>{let j=i;if(event.key==='ArrowRight')j=(i+1)%buttons.length;else if(event.key==='ArrowLeft')j=(i+buttons.length-1)%buttons.length;else if(event.key==='Home')j=0;else if(event.key==='End')j=buttons.length-1;else return;event.preventDefault();buttons[j].focus();activate(buttons[j].dataset.tab);});});
document.getElementById('tabNav').setAttribute('role','tablist');
document.getElementById('heroMeta').innerHTML=Object.values(DATA.platforms).map(p=>'<span><b>'+platformName(p.platform)+' '+esc(p.summary.version)+'</b>Build '+esc(p.summary.build)+'</span>').join('')+'<span>'+esc([...new Set(Object.values(DATA.platforms).map(p=>p.summary.date).filter(Boolean))].join(' · '))+'</span>';
document.getElementById('heroActions').innerHTML=Object.keys(DATA.platforms).filter(key=>DATA.links[key]?.pdf).map(key=>'<a class="button primary" href="'+esc(DATA.links[key].pdf)+'" download>PDF '+platformName(key)+' ↓</a>').join('');
const activateHash=()=>{const hash=decodeURIComponent(location.hash.slice(1));const match=hash.match(/^(ios|android)-/);if(match&&DATA.platforms[match[1]]){activate(match[1]);const target=document.getElementById(hash);if(target)target.scrollIntoView();}else if(['recap','ios','android','insights'].includes(hash))activate(hash);};
activate(DATA.initial||'recap');if(location.hash)activateHash();window.addEventListener('hashchange',activateHash);
window.addEventListener('beforeprint',()=>{printing=true;Object.keys(DATA.platforms).forEach(key=>{if(!rendered.has(key)){renderPlatform(key);rendered.add(key);}});window.dispatchEvent(new Event('audit-print'));document.querySelectorAll('.disclosure,.finding,.cell-details').forEach(d=>{d.dataset.printWasOpen=String(d.open);d.open=true;});});
window.addEventListener('afterprint',()=>{printing=false;document.querySelectorAll('[data-print-was-open]').forEach(d=>{d.open=d.dataset.printWasOpen==='true';delete d.dataset.printWasOpen;});window.dispatchEvent(new Event('audit-print'));});
})();
'''
def standard_html(title,platforms,initial='recap',links=None):
 # Older cached models can be restyled without exposing deferred localization data.
 platforms={key:{**value,'blocks':[b for b in value.get('blocks',[]) if b.get('key')!='localization']} for key,value in platforms.items()}
 data={'schemaVersion':SCHEMA_VERSION,'title':title,'platforms':platforms,'initial':initial,'links':links or {}}
 serialized=json.dumps(data,ensure_ascii=False).replace('<',chr(92)+'u003c')
 return '<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+html.escape(title)+' — Audit mobile</title><style>'+STYLE+'</style></head><body><a class="skip-link" href="#reportContent">Vai al report</a><div class="brandbar"><div class="brandbar-inner"><span class="brand"><span class="brand-mark" aria-hidden="true">FR</span>FRTMTools<span class="brand-context">/ Audit mobile</span></span><span class="brand-context">Report applicativo</span></div></div><header class="hero"><div class="hero-inner"><div><h1>'+html.escape(title)+'</h1><p>Dimensioni, componenti e segnalazioni di sicurezza</p><div class="hero-meta" id="heroMeta"></div></div><div class="hero-actions" id="heroActions"></div></div></header><nav class="tabs" aria-label="Sezioni del report"><div class="tabs-inner" id="tabNav"><button data-tab="recap">Sintesi</button><button data-tab="ios">Analisi iOS</button><button data-tab="android">Analisi Android</button><button data-tab="insights">Insight</button></div></nav><main id="reportContent"><div id="tab-recap" class="tab-content active"></div><div id="tab-ios" class="tab-content"></div><div id="tab-android" class="tab-content"></div><div id="tab-insights" class="tab-content"></div><footer class="report-footer"><span>FRTMTools · Standard 1.3</span><span>Segnalazioni statiche e advisory candidati · Sfruttabilità non confermata</span></footer></main><script>const DATA='+serialized+';</script><script>'+SCRIPT+'</script></body></html>'


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
