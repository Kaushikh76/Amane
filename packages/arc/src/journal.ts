import { mkdir, readFile, rename, writeFile, open, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { keccak256, toHex, type Hex } from 'viem';
export interface RelayRecord {intentHash:Hex;rawTransaction?:Hex;transactionHash?:Hex;status:'RESERVED'|'SIGNED'|'BROADCAST'}
/** Atomic mkdir reserves an obligation across processes; crash in RESERVED needs human reconciliation.
 * Signed bytes are persisted before submission; restart rebroadcasts those same bytes. */
export class FileRelayJournal {
 constructor(readonly directory:string) {}
 private path(key:string) {if(!key || key.length>512)throw new Error('INVALID_IDEMPOTENCY_KEY');return join(this.directory,keccak256(toHex(key)).slice(2));}
 async read(key:string):Promise<RelayRecord|undefined> {try{return JSON.parse(await readFile(join(this.path(key),'record.json'),'utf8')) as RelayRecord;}catch(e){if((e as NodeJS.ErrnoException).code==='ENOENT')return undefined;throw e;}}
 async reserve(key:string,intentHash:Hex):Promise<boolean> {
  await mkdir(this.directory,{recursive:true,mode:0o700});
  try{await mkdir(this.path(key),{mode:0o700});}catch(e){if((e as NodeJS.ErrnoException).code==='EEXIST')return false;throw e;}
  await this.save(key,{intentHash,status:'RESERVED'});return true;
 }
 async save(key:string,record:RelayRecord) {const path=join(this.path(key),'record.json');await this.atomic(path,record);}
 private async atomic(path:string,value:unknown) {
  const file=await open(path+'.tmp','w',0o600);try{await file.writeFile(JSON.stringify(value));await file.sync();}finally{await file.close();}
  await rename(path+'.tmp',path);
  const directory=await open(path.slice(0,path.lastIndexOf('/')),'r');try{await directory.sync();}finally{await directory.close();}
 }
 /** One journal directory must be shared by every process using the same gas payer. A crash
  * holding this lock or a reserved but unsigned nonce requires operator reconciliation. */
 async reserveNonce(chainId:number,relayer:string,pendingNonce:number):Promise<number> {
  const path=join(this.directory,`nonce-${chainId}-${relayer.toLowerCase()}`),lock=path+'.lock';
  try{await mkdir(lock,{mode:0o700});}catch(e){if((e as NodeJS.ErrnoException).code==='EEXIST')throw new Error('RELAYER_BUSY_OR_RECONCILIATION_REQUIRED');throw e;}
  try{let stored=pendingNonce;try{stored=Number(JSON.parse(await readFile(path,'utf8')).next);}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}
   if(!Number.isSafeInteger(stored) || stored<0)throw new Error('CORRUPT_NONCE_JOURNAL');
   const nonce=Math.max(stored,pendingNonce);await this.atomic(path,{next:nonce+1});return nonce;
  }finally{await rmdir(lock);}
 }
}
