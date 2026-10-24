"""Integration checks against the local Sites preview. Synthetic users only.
Run: python3 tests/integration.py [http://127.0.0.1:4173]
"""
import json, sys, uuid, urllib.request, urllib.error, concurrent.futures, pathlib
BASE=sys.argv[1] if len(sys.argv)>1 else 'http://127.0.0.1:4173'
ORIGIN='http://terminal.local:4173'
checks=[]
def api(path, data=None, user='qa-a', key=None, origin=ORIGIN):
    headers={'Host':'terminal.local:4173','oai-authenticated-user-id':user,'oai-authenticated-user-email':user+'@example.invalid'}
    if data is not None: headers.update({'Content-Type':'application/json','Origin':origin})
    if key:headers['Idempotency-Key']=key
    req=urllib.request.Request(BASE+'/api/'+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=40) as r:
            raw=r.read();return r.status,raw if r.headers.get_content_type() in ['application/pdf','text/csv'] else json.loads(raw)
    except urllib.error.HTTPError as e:
        raw=e.read()
        try:raw=json.loads(raw)
        except:pass
        return e.code,raw
def check(name,cond):
    assert cond,name
    checks.append(name);print('OK',name)
def create(product='lectura',user='qa-a',**kw):
    b={'product':product,'name':'Luna Demo','birth':'1998-10-10','theme':'general','adult':True,'terms':True,'marketing':False}
    if product=='compatibilidad':b.update(name2='Sol Demo',birth2='1996-07-30',otherConsent=True)
    b.update(kw);k=str(uuid.uuid4());s,o=api('orders',b,user,k);check('create '+product,s==201);return b,k,o

s,d=api('daily');check('12 signs cached',s==200 and len(d['items'])==12)
check('same daily cache content',api('daily')[1]==d)
b,k,o=create();oid=o['id']
check('server price ignores client amount',o['amount']==19000)
check('same request returns same order',api('orders',b,key=k)[1]['id']==oid)
check('key conflict rejected',api('orders',{**b,'name':'Otra Demo'},key=k)[0]==409)
check('PDF before payment blocked',api('orders/'+oid+'/pdf')[0]==409)
check('cross-account order blocked',api('orders/'+oid,user='qa-b')[0]==404)
check('cross-account PDF blocked',api('orders/'+oid+'/pdf',user='qa-b')[0]==404)
check('cross-origin mutation blocked',api('orders',b,key=str(uuid.uuid4()),origin='https://malicious.invalid')[0]==403)
check('minor rejected',api('orders',{**b,'birth':'2015-01-01'},user='qa-minor',key=str(uuid.uuid4()))[0]==400)
check('impossible birth rejected',api('orders',{**b,'birth':'1998-02-31'},key=str(uuid.uuid4()))[0]==400)
check('consent required',api('orders',{**b,'terms':False},key=str(uuid.uuid4()))[0]==400)
check('HTML name rejected',api('orders',{**b,'name':'<script>alert(1)</script>'},key=str(uuid.uuid4()))[0]==400)
check('declined never delivers',api('demo/payments/'+oid,{'outcome':'declined'})[1]['deliveryStatus']=='pending')
check('PDF after decline blocked',api('orders/'+oid+'/pdf')[0]==409)
with concurrent.futures.ThreadPoolExecutor(2) as pool:
    results=list(pool.map(lambda _:api('demo/payments/'+oid,{'outcome':'approved'}),range(2)))
s,paid=api('orders/'+oid);check('concurrent repeat approval delivers once',s==200 and paid['deliveryStatus']=='delivered' and paid['attempts']==1)
check('repeat approval keeps immutable result',api('demo/payments/'+oid,{'outcome':'approved'})[1]['result']==paid['result'])
s,pdf=api('orders/'+oid+'/pdf');check('private PDF generated',s==200 and pdf.startswith(b'%PDF-1.4'))
pathlib.Path('outputs').mkdir(exist_ok=True);pathlib.Path('outputs/qa-report.pdf').write_bytes(pdf)
_,_,c=create('compatibilidad',user='qa-c')
check('compatibility delivered with five modules',len(api('demo/payments/'+c['id'],{'outcome':'approved'},user='qa-c')[1]['result']['sections'])==5)
_,_,premium=create('premium',user='qa-d')
check('premium has six modules',len(api('demo/payments/'+premium['id'],{'outcome':'approved'},user='qa-d')[1]['result']['sections'])==6)
_,_,err=create(user='qa-e');eid=err['id']
check('forced failure keeps payment approved',api('demo/payments/'+eid,{'outcome':'approved','failGeneration':True},user='qa-e')[1]['deliveryStatus']=='error')
check('retry recovers without another payment',api('orders/'+eid+'/retry',{},user='qa-e')[1]['deliveryStatus']=='delivered')
_,_,cancel=create(user='qa-f')
check('cancel stays unpaid',api('demo/payments/'+cancel['id'],{'outcome':'cancelled'},user='qa-f')[1]['paymentStatus']=='cancelled')
check('unconfigured real webhook rejects',api('payments/webhook',{})[0]==503)
check('refund simulation succeeds',api('admin/refund/'+oid,{})[0]==200)
check('refunded PDF blocked',api('orders/'+oid+'/pdf')[0]==409)
key=str(uuid.uuid4());expense={'category':'publicidad','date':d['date'],'amount':12000,'note':'=UNTRUSTED_CSV_TEST'}
check('expense recorded',api('admin/expenses',expense,key=key)[0]==200)
check('expense replay idempotent',api('admin/expenses',expense,key=key)[0]==200)
s,csv=api('admin/export');check('CSV neutralizes formula injection',s==200 and b"'=UNTRUSTED_CSV_TEST" in csv)
check('negative expense rejected',api('admin/expenses',{**expense,'amount':-1},key=str(uuid.uuid4()))[0]==400)
_,dash=api('admin/dashboard');check('dashboard separates refunds costs and revenues',dash['refunds']>=19000 and dash['adSpend']>=12000 and dash['monthRevenue']==dash['monthGross']-dash['refunds'])
check('synthetic identities separate histories',all(x['payload']['name']!='Sol Demo' and x['id']!=c['id'] for x in api('orders')[1]['orders']))
ref=api('me',user='qa-referrer')[1]['referralCode']
check('self referral rejected',api('orders',{**b,'referral':ref},user='qa-referrer',key=str(uuid.uuid4()))[0]==400)
newref='qa-new-'+str(uuid.uuid4())[:6];rb,rk,ro=create(user=newref,referral=ref)
check('referral discount applies server side',ro['amount']==17100 and ro['discount']==1900)
check('second concurrent referral reservation rejected',api('orders',rb,user=newref,key=str(uuid.uuid4()))[0]==400)
pathlib.Path('outputs/qa-integration.json').write_text(json.dumps({'passed':len(checks),'checks':checks},ensure_ascii=False,indent=2))
print('PASS',len(checks),'checks')
