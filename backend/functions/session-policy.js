// Check server-side revocation on every data operation, not only JWT expiry.
export async function verifiedSession(request, auth) {
  const header = request.rawRequest?.headers?.authorization || '';
  const token = /^Bearer (\S+)$/i.exec(header)?.[1];
  if (!token || !request.auth?.uid) throw new Error('unauthenticated');
  const decoded = await auth.verifyIdToken(token, true);
  if (decoded.uid !== request.auth.uid) throw new Error('unauthenticated');
  // Admin's ordinary revocation comparison is second-granular. Require a
  // sign-in strictly after the current server cutoff, including its boundary.
  // Re-fetch on every operation: never trust a cached client account profile.
  const account = await auth.getUser(decoded.uid);
  if (account.uid !== decoded.uid || account.disabled) throw new Error('unauthenticated');
  assertAfterCutoff(decoded, Date.parse(account.tokensValidAfterTime) / 1000);
  return decoded;
}
export function assertAfterCutoff(decoded, cutoff) {
  if(cutoff != null && (!Number.isFinite(cutoff) || !Number.isFinite(decoded.auth_time)
    || decoded.auth_time <= cutoff))
    throw new Error('auth/id-token-revoked');
}
export function validateRecords(records) {
  if (!Array.isArray(records) || records.length > 100) throw new Error('invalid-argument');
  const types = ['tasks','projects','events','filters','settings'];
  const seen = new Set();
  return records.map(record => {
    if (!record || typeof record !== 'object' || !types.includes(record.type)
      || typeof record.id !== 'string' || record.id.length < 1 || record.id.length > 200
      || typeof record.deleted !== 'boolean' || typeof record.mutation !== 'string'
      || record.mutation.length > 100 || !record.data || typeof record.data !== 'object'
      || Array.isArray(record.data) || JSON.stringify(record.data).length > 200000
      || Object.keys(record).some(k => !['type','id','data','deleted','mutation'].includes(k)))
      throw new Error('invalid-argument');
    const key = record.type === 'settings' ? 'settings' : `${record.type}-${encodeURIComponent(record.id)}`;
    if(seen.has(key)) throw new Error('invalid-argument');
    seen.add(key);
    return {key,value:record};
  });
}
