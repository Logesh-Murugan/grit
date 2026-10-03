import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, FieldValue, FieldPath} from 'firebase-admin/firestore';
import {verifiedSession, validateRecords, assertAfterCutoff} from './session-policy.js';
initializeApp();
const db=getFirestore(), auth=getAuth();
const options={region:'asia-south1',maxInstances:3,timeoutSeconds:30};
async function session(request) {
  try {
    const user=await verifiedSession(request,auth);
    const policy=await db.doc(`privateSessions/${user.uid}`).get();
    assertAfterCutoff(user,policy.data()?.revokedAt);
    return user;
  }
  catch {throw new HttpsError('unauthenticated','Your session ended. Sign in again.');}
}
// No client uid or path accepted; the verified token owns the operation.
export const writeRecords=onCall(options,async request=>{
  const user=await session(request);
  let records;
  try {records=validateRecords(request.data?.records);}
  catch {throw new HttpsError('invalid-argument','Invalid workspace records.');}
  const batch=db.batch();
  for(const record of records) batch.set(db.doc(`users/${user.uid}/records/${record.key}`),
    {...record.value,updatedAt:FieldValue.serverTimestamp()});
  if(records.length) await batch.commit();
  return {saved:records.length};
});
// Paginated full snapshot includes tombstones. Direct Firestore is denied.
export const readRecords=onCall(options,async request=>{
  const user=await session(request);
  const after=request.data?.after;
  if(after!=null && (typeof after!=='string'||after.length>800||after.includes('/')))
    throw new HttpsError('invalid-argument','Invalid cursor.');
  let query=db.collection(`users/${user.uid}/records`).orderBy(FieldPath.documentId()).limit(100);
  if(after) query=query.startAfter(after);
  const snapshot=await query.get();
  return {records:snapshot.docs.map(d=>({key:d.id,...d.data(),updatedAt:null})),
    after:snapshot.size===100?snapshot.docs.at(-1).id:null};
});
export const revokeAllSessions=onCall(options,async request=>{
  const user=await session(request);
  if(!Number.isFinite(user.auth_time)||Date.now()/1000-user.auth_time>300)
    throw new HttpsError('failed-precondition','Sign in again before ending every session.');
  // Millisecond cutoff closes the same-second auth_time comparison edge.
  const policy = db.doc(`privateSessions/${user.uid}`);
  const cutoff = Date.now()/1000;
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(policy);
    const previous = existing.data()?.revokedAt;
    transaction.set(policy, {revokedAt:Math.max(cutoff,
      Number.isFinite(previous) ? previous : 0)}, {merge:true});
  });
  await auth.revokeRefreshTokens(user.uid);
  return {revoked:true};
});
// AI omitted at the owner's request; no AI API key or calls.
