import {parseTransaction,recoverTransactionAddress,keccak256,type TransactionSerializedEIP1559,type TransactionSerializableEIP1559} from 'viem';
import {FileRelayJournal} from './journal.js';
import type {IsolatedSigner,RelayResult} from './index.js';
export interface AuthorityBroadcastApproval {chainId:number;account:Address;relayer:Address;maxGas:bigint;maxFeePerGas:bigint}
import { encodeFunctionData,getAddress,hashTypedData,type Address,type Hex,type PublicClient,type WalletClient } from 'viem';
import { type RootPolicy,type AgentLease,type ActionIntent } from '@amane/core';
import { authorityTypedData,validateAuthorityAction,authorityDigest,authorityActionSchema,type AuthorityContext } from '@amane/policy/authority';
import { assertResolvedAuthorityPolicy,type ResolvedAuthorityPolicy } from '@amane/policy/authority-registry';
import {authorityArtifacts} from './authority-artifacts.js';
export {authorityArtifacts};
export type {RootPolicy,AgentLease,ActionIntent};
export interface AuthorityDeployment {chainId:number;account:Address;accountCodeHash:Hex;extension:Address;extensionCodeHash:Hex}
/** New authority client; explicit deployment identity is mandatory. No implicit live v3 address. */
export class AuthorityClient {
 constructor(readonly publicClient:PublicClient,readonly deployment:AuthorityDeployment){}
 async checkIdentity():Promise<void>{const {keccak256}=await import('viem');if(await this.publicClient.getChainId()!==this.deployment.chainId)throw Error('CHAIN_MISMATCH');for(const [address,hash] of [[this.deployment.account,this.deployment.accountCodeHash],[this.deployment.extension,this.deployment.extensionCodeHash]] as const){const code=await this.publicClient.getCode({address});if(!code||code==='0x'||keccak256(code)!==hash)throw Error('AUTHORITY_CODE_MISMATCH');}const ext=await this.publicClient.readContract({address:this.deployment.account,abi:authorityArtifacts.ArcAuthority.abi,functionName:'ext'});if(getAddress(ext)!==getAddress(this.deployment.extension))throw Error('EXTENSION_MISMATCH');}
 async signPolicy(resolved:ResolvedAuthorityPolicy,wallet:WalletClient):Promise<Hex>{assertResolvedAuthorityPolicy(resolved);if(resolved.chainId!==this.deployment.chainId||getAddress(resolved.account)!==getAddress(this.deployment.account))throw Error('POLICY_ENDPOINT_MISMATCH');await this.checkIdentity();const registry=await this.publicClient.readContract({address:this.deployment.account,abi:authorityArtifacts.ArcAuthority.abi,functionName:'registry'});if(getAddress(registry)!==getAddress(resolved.registry))throw Error('RESOLVED_REGISTRY_MISMATCH');if(!wallet.account)throw Error('SIGNER_REQUIRED');return wallet.signTypedData({...authorityTypedData(this.deployment.chainId,this.deployment.account,'RootPolicy',resolved.policy),account:wallet.account} as never);}
 async simulate(action:ActionIntent,signature:Hex,relayer:Address){await this.checkIdentity();return this.publicClient.simulateContract({address:this.deployment.account,abi:authorityArtifacts.ArcAuthority.abi,functionName:'executeAction',args:[action,signature],account:relayer});}
 prepareAction(p:RootPolicy,l:AgentLease,a:unknown,ctx:AuthorityContext){if(ctx.chainId!==this.deployment.chainId||getAddress(ctx.account)!==getAddress(this.deployment.account))throw Error('CONTEXT_MISMATCH');const checked=validateAuthorityAction(p,l,a,ctx);return {...checked,typedData:authorityTypedData(ctx.chainId,ctx.account,'ActionIntent',checked.action),digest:hashTypedData(authorityTypedData(ctx.chainId,ctx.account,'ActionIntent',checked.action) as never)};}
 encodeExecute(a:ActionIntent,signature:Hex){return {to:this.deployment.account,chainId:this.deployment.chainId,value:0n,data:encodeFunctionData({abi:authorityArtifacts.ArcAuthority.abi,functionName:'executeAction',args:[a,signature]})};}
 async relay(action:ActionIntent,signature:Hex,key:string,journal:FileRelayJournal,signer:IsolatedSigner,approval:AuthorityBroadcastApproval):Promise<RelayResult> {
  await this.checkIdentity();const chainId=this.deployment.chainId;
  if(chainId!==approval.chainId || approval.account.toLowerCase()!==this.deployment.account.toLowerCase() || approval.maxGas<=0n || approval.maxFeePerGas<=0n)throw new Error('BROADCAST_NOT_APPROVED');
  authorityActionSchema.parse(action);const intentHash=authorityDigest(chainId,this.deployment.account,'ActionIntent',action);
  const data=encodeFunctionData({abi:authorityArtifacts.ArcAuthority.abi,functionName:'executeAction',args:[action,signature]});
  const validateRaw=async(raw:Hex)=>{
   if(!raw.startsWith('0x02'))throw new Error('SIGNER_TRANSACTION_TYPE');
   const serialized=raw as TransactionSerializedEIP1559,t=parseTransaction(serialized);
   if(t.chainId!==chainId || t.to?.toLowerCase()!==this.deployment.account.toLowerCase() || t.data!==data || (t.value??0n)!==0n || !t.gas || t.gas>approval.maxGas || t.maxFeePerGas===undefined || t.maxFeePerGas>approval.maxFeePerGas || (await recoverTransactionAddress({serializedTransaction:serialized})).toLowerCase()!==approval.relayer.toLowerCase())throw new Error('SIGNER_TRANSACTION_MISMATCH');
   return t;
  };
  const existing=await journal.read(key);
  if(existing && existing.intentHash!==intentHash)throw new Error('IDEMPOTENCY_CONFLICT');
  if(existing?.rawTransaction && existing.transactionHash) {
   await validateRaw(existing.rawTransaction);
   if(keccak256(existing.rawTransaction)!==existing.transactionHash)throw new Error('CORRUPT_JOURNAL');
   const hash=await this.publicClient.sendRawTransaction({serializedTransaction:existing.rawTransaction});
   if(hash!==existing.transactionHash)throw new Error('TRANSACTION_HASH_MISMATCH');
   return {status:'BROADCAST',intentHash,transactionHash:hash};
  }
  if(existing || !await journal.reserve(key,intentHash))return {status:'NEEDS_RECONCILIATION',intentHash};
  await this.simulate(action,signature,approval.relayer);
  const tx:TransactionSerializableEIP1559={type:'eip1559',chainId,nonce:await journal.reserveNonce(chainId,approval.relayer,await this.publicClient.getTransactionCount({address:approval.relayer,blockTag:'pending'})),to:this.deployment.account,data,value:0n,gas:approval.maxGas,maxFeePerGas:approval.maxFeePerGas,maxPriorityFeePerGas:0n};
  const raw=await signer.signTransaction(tx);const signed=await validateRaw(raw);
  if(signed.nonce!==tx.nonce || signed.gas!==tx.gas || signed.maxFeePerGas!==tx.maxFeePerGas || (signed.maxPriorityFeePerGas??0n)!==0n)throw new Error('SIGNER_TRANSACTION_MISMATCH');
  const hash=keccak256(raw);await journal.save(key,{intentHash,rawTransaction:raw,transactionHash:hash,status:'SIGNED'});
  const submitted=await this.publicClient.sendRawTransaction({serializedTransaction:raw});if(submitted!==hash)throw new Error('TRANSACTION_HASH_MISMATCH');
  await journal.save(key,{intentHash,rawTransaction:raw,transactionHash:hash,status:'BROADCAST'});
  return {status:'BROADCAST',intentHash,transactionHash:hash};
 }
}
