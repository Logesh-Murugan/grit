import {test} from 'node:test';
import assert from 'node:assert/strict';
import {verifiedSession,validateRecords,assertAfterCutoff} from './session-policy.js';
const account={uid:'alice',disabled:false,tokensValidAfterTime:new Date(99000).toISOString()};
const getUser=async()=>account;
const request={auth:{uid:'alice'},rawRequest:{headers:{authorization:'Bearer token'}}};
test('explicit cutoff rejects old and same-second sessions, permits fresh sign-in',()=>{
  assert.throws(()=>assertAfterCutoff({auth_time:100},100.5));
  assert.throws(()=>assertAfterCutoff({auth_time:99},100.5));
  assert.throws(()=>assertAfterCutoff({},100.5));
  assert.doesNotThrow(()=>assertAfterCutoff({auth_time:101},100.5));
});
test('Admin revocation check is enabled on every request',async()=>{
  let count=0;
  const auth={getUser,verifyIdToken:async(token,checkRevoked)=>{
    count++;assert.equal(token,'token');assert.equal(checkRevoked,true);return {uid:'alice',auth_time:101};
  }};
  await verifiedSession(request,auth);await verifiedSession(request,auth);
  assert.equal(count,2);
});
for(const reason of ['password change','MFA enrollment','administrator revocation']) {
  test(`old session is rejected after ${reason}`,async()=>{
    let revoked=false;
    const auth={getUser,verifyIdToken:async(_,checkRevoked)=>{
      assert.equal(checkRevoked,true);
      if(revoked)throw new Error('auth/id-token-revoked');return {uid:'alice',auth_time:101};
    }};
    await verifiedSession(request,auth);revoked=true;
    await assert.rejects(verifiedSession(request,auth),/revoked/);
  });
}
test('missing bearer, absent callable identity and uid mismatch fail closed',async()=>{
  const auth={getUser,verifyIdToken:async()=>({uid:'bob'})};
  await assert.rejects(verifiedSession({},auth));
  await assert.rejects(verifiedSession({...request,auth:null},auth));
  await assert.rejects(verifiedSession(request,auth));
});
test('Admin service errors cannot bypass session enforcement',async()=>{
  await assert.rejects(verifiedSession(request,{verifyIdToken:async()=>{throw new Error('network');}}));
});
test('schema validates records, strips path injection through encoding',()=>{
  const record={type:'tasks',id:'../other',data:{title:'Study'},deleted:false,mutation:'v1'};
  assert.equal(validateRecords([record])[0].key,'tasks-..%2Fother');
  for(const invalid of [null,{...record,uid:'bob'},{...record,type:'subscriptions'},
    {...record,data:[]},{...record,deleted:'false'},{...record,mutation:1}])
    assert.throws(()=>validateRecords([invalid]));
  assert.throws(()=>validateRecords([record,record]));
  assert.throws(()=>validateRecords(Array(101).fill(record)));
});

test('password or MFA cutoff rejects existing ID tokens even when Admin accepts equal-second auth',async()=>{
  let cutoff=99000;
  const auth={verifyIdToken:async()=>({uid:'alice',auth_time:101}),
    getUser:async()=>({...account,tokensValidAfterTime:new Date(cutoff).toISOString()})};
  await verifiedSession(request,auth);
  cutoff=101000;
  await assert.rejects(verifiedSession(request,auth),/revoked/);
  auth.verifyIdToken=async()=>({uid:'alice',auth_time:102});
  await verifiedSession(request,auth);
});
test('account policy is refreshed on each request, disabled users fail closed',async()=>{
  let calls=0;
  const auth={verifyIdToken:async()=>({uid:'alice',auth_time:101}),
    getUser:async()=>{calls++; return {...account,disabled:calls>1};}};
  await verifiedSession(request,auth);
  await assert.rejects(verifiedSession(request,auth));
  assert.equal(calls,2);
});
test('malformed account or policy cutoffs and failed account lookup fail closed',async()=>{
  for(const cutoff of [NaN,Infinity,'100']) assert.throws(()=>assertAfterCutoff({auth_time:101},cutoff));
  const auth={verifyIdToken:async()=>({uid:'alice',auth_time:101}),
    getUser:async()=>({...account,tokensValidAfterTime:'invalid'})};
  await assert.rejects(verifiedSession(request,auth));
  auth.getUser=async()=>{throw new Error('unavailable');};
  await assert.rejects(verifiedSession(request,auth));
});
