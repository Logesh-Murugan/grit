import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,collection,getDocs} from 'firebase/firestore';
const rules=await readFile(process.env.GRIT_SECURE_RULES_PATH || new URL('../firestore.secure.rules',import.meta.url),'utf8');
const env=await initializeTestEnvironment({projectId:'demo-grit',firestore:{host:'127.0.0.1',port:8088,rules}});
let checks=0;
async function check(name,operation){await operation;checks++;console.log('PASS '+name);}
try {
  await env.withSecurityRulesDisabled(async context=>{
    await check('trusted server context can write',assertSucceeds(setDoc(doc(context.firestore(),'users/alice/records/tasks-a'),{title:'Study'})));
  });
  for(const [name,context] of [
    ['owner',env.authenticatedContext('alice')],
    ['other user',env.authenticatedContext('bob')],
    ['anonymous',env.unauthenticatedContext()]]) {
    const db=context.firestore();
    await check(`${name} cannot bypass server read checks`,assertFails(getDoc(doc(db,'users/alice/records/tasks-a'))));
    await check(`${name} cannot bypass server write checks`,assertFails(setDoc(doc(db,'users/alice/records/tasks-a'),{title:'Attack'})));
    await check(`${name} cannot list data directly`,assertFails(getDocs(collection(db,'users/alice/records'))));
  }
  console.log(`${checks} secure rules checks passed`);
} finally {await env.cleanup();}
