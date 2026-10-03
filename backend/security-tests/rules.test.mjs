import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,deleteDoc,collection,getDocs,serverTimestamp} from 'firebase/firestore';
const rules=await readFile(new URL('../firestore.rules',import.meta.url),'utf8');
const env=await initializeTestEnvironment({projectId:'demo-grit',firestore:{host:'127.0.0.1',port:8088,rules}});
const a=env.authenticatedContext('alice').firestore(), b=env.authenticatedContext('bob').firestore(), anonymous=env.unauthenticatedContext().firestore();
const record={type:'tasks',id:'task-1',data:{id:'task-1',title:'Only Alice'},deleted:false,mutation:'test-1',updatedAt:serverTimestamp()};
let checks=0;
async function check(name,operation){await operation;checks++;console.log('PASS '+name);}
try {
await check('owner creates own task',assertSucceeds(setDoc(doc(a,'users/alice/records/tasks-task-1'),record)));
await check('owner reads own task',assertSucceeds(getDoc(doc(a,'users/alice/records/tasks-task-1'))));
await check('other user cannot read',assertFails(getDoc(doc(b,'users/alice/records/tasks-task-1'))));
await check('other user cannot write',assertFails(setDoc(doc(b,'users/alice/records/tasks-task-1'),record)));
await check('anonymous cannot read',assertFails(getDoc(doc(anonymous,'users/alice/records/tasks-task-1'))));
await check('anonymous cannot write',assertFails(setDoc(doc(anonymous,'users/alice/records/tasks-task-1'),record)));
await check('owner lists own records',assertSucceeds(getDocs(collection(a,'users/alice/records'))));
await check('other user cannot list',assertFails(getDocs(collection(b,'users/alice/records'))));
await check('unknown record type denied',assertFails(setDoc(doc(a,'users/alice/records/invalid'),{...record,type:'secret'})));
await check('unknown top-level field denied',assertFails(setDoc(doc(a,'users/alice/records/invalid'),{...record,role:'admin'})));
await check('malformed payload denied',assertFails(setDoc(doc(a,'users/alice/records/invalid'),{...record,data:'invalid'})));
await check('physical delete denied',assertFails(deleteDoc(doc(a,'users/alice/records/tasks-task-1'))));
await check('tombstone allowed for owner',assertSucceeds(setDoc(doc(a,'users/alice/records/tasks-task-1'),{...record,deleted:true})));
await check('client cannot grant subscription',assertFails(setDoc(doc(a,'users/alice/subscriptions/premium'),{active:true})));
await check('unknown collection denied',assertFails(setDoc(doc(a,'teams/test'),{owner:'alice'})));
console.log(`${checks} security checks passed`);
} finally {await env.cleanup();}
