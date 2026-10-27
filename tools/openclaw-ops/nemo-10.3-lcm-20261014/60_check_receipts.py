import pathlib,json,sqlite3,subprocess,sys,re
s,b=map(pathlib.Path,sys.argv[1:]);out={}
def read_receipt(f):
 text=f.read_text()
 for i,c in enumerate(text):
  if c!='{':continue
  try:d,end=json.JSONDecoder().raw_decode(text[i:]);return d
  except Exception:continue
 raise ValueError('receipt has no complete JSON')
for name,marker,winner in [('live-muse','UAT_MUSE_LCM_OK','meta/muse-spark-1.3-contributor'),('live-recall-discovery','SEN-731','meta/muse-spark-1.3-contributor'),('live-sol61','UAT_SOL61_LCM_OK','gpt-6.1-sol')]:
 d=read_receipt(b/(name+'.json'));assert d['status']=='ok';r=d['result'];meta=r['meta'];trace=meta['executionTrace'];assert trace['winnerModel']==winner;assert any(marker in p.get('text','') for p in r['payloads']);out[name]={'status':d['status'],'winnerModel':trace['winnerModel'],'winnerProvider':trace.get('winnerProvider'),'attempts':len(trace.get('attempts',[])),'fallbackUsed':trace.get('fallbackUsed'),'durationMs':meta.get('durationMs')};assert r.get('sourceReplyDeliveryState') in [None,'missing','not-requested'], 'unexpected delivery state'
db=sqlite3.connect((s/'config/lcm.db').as_uri()+'?mode=ro',uri=True);assert db.execute('pragma quick_check').fetchone()[0]=='ok';out['lcm']={'messages':db.execute('select count(*) from messages').fetchone()[0],'conversations':db.execute('select count(*) from conversations').fetchone()[0],'grep_parts':db.execute("select count(*) from message_parts where (tool_name='lcm_grep' or (tool_name='tool_call' and tool_input like '%lcm_grep%'))").fetchone()[0]};out['lcm']['grep_result_marker_parts']=db.execute("select count(*) from messages m join message_parts p on m.message_id=p.message_id where m.role='tool' and p.text_content like '%SEN-731%'").fetchone()[0];assert out['lcm']['messages']>0;assert out['lcm']['grep_parts']>0;assert out['lcm']['grep_result_marker_parts']>0;db.close()
before=json.loads((b/'unaffected-services.json').read_text());after={}
for p in ['hungreo','suckhoe']:
 after[p]={k:subprocess.check_output(['systemctl','--user','show',f'openclaw-gateway-{p}.service','-p',k,'--value'],text=True).strip() for k in ['MainPID','NRestarts','ActiveState']}
assert before==after,'unaffected service state changed';out['unaffected_services']=after
inspect=json.loads(subprocess.check_output(['docker','inspect','nemo-sandbox'],text=True))[0];old=json.loads((b/'container-inspect.json').read_text())[0]
for k in ['Memory','MemorySwap','NanoCpus','PortBindings','LogConfig']:
 assert inspect['HostConfig'][k]==old['HostConfig'][k], 'container invariant drift: '+k
assert inspect['Config']['User']==old['Config']['User'];out['container']={'StartedAt':inspect['State']['StartedAt'],'RestartCount':inspect['RestartCount'],'OOMKilled':inspect['State']['OOMKilled'],'memoryLimitBytes':inspect['HostConfig']['Memory']}
(b/'verification-summary.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False))
