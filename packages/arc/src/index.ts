import { encodeFunctionData, keccak256, parseTransaction, recoverTransactionAddress, type Address, type Hex, type PublicClient, type TransactionSerializedEIP1559, type TransactionSerializableEIP1559 } from 'viem';
import { actionHash, actionSchema, type ActionIntent } from '@amane/policy';
import { artifacts } from './artifacts.js';
import { verifyDeployment } from './registry.js';
import { FileRelayJournal } from './journal.js';
export * from './registry.js';export * from './journal.js';export {artifacts};
export type RelayResult = {status:'BROADCAST';intentHash:Hex;transactionHash:Hex}|{status:'NEEDS_RECONCILIATION';intentHash:Hex};
export interface BroadcastApproval {chainId:5042002|31337;account:Address;maxGas:bigint;maxFeePerGas:bigint;relayer:Address}
export interface IsolatedSigner {signTransaction(tx:TransactionSerializableEIP1559):Promise<Hex>}
export class ArcClient {
 constructor(readonly client:PublicClient,readonly address:Address,readonly codeHash:Hex) {}
 async verify():Promise<number> {await verifyDeployment(this.client,this.address,this.codeHash);return this.client.getChainId();}
 async simulate(action:ActionIntent,signature:Hex,relayer:Address) {
  await this.verify();actionSchema.parse(action);
  return this.client.simulateContract({address:this.address,abi:artifacts.ArcAccount.abi,functionName:'execute',args:[action,signature],account:relayer});
 }
 async relay(action:ActionIntent,signature:Hex,key:string,journal:FileRelayJournal,signer:IsolatedSigner,approval:BroadcastApproval):Promise<RelayResult> {
  const chainId=await this.verify();
  if(chainId!==approval.chainId || approval.account.toLowerCase()!==this.address.toLowerCase() || approval.maxGas<=0n || approval.maxFeePerGas<=0n)throw new Error('BROADCAST_NOT_APPROVED');
  actionSchema.parse(action);const intentHash=actionHash(action,chainId,this.address);
  const data=encodeFunctionData({abi:artifacts.ArcAccount.abi,functionName:'execute',args:[action,signature]});
  const validateRaw=async(raw:Hex)=>{
   if(!raw.startsWith('0x02'))throw new Error('SIGNER_TRANSACTION_TYPE');
   const serialized=raw as TransactionSerializedEIP1559,t=parseTransaction(serialized);
   if(t.chainId!==chainId || t.to?.toLowerCase()!==this.address.toLowerCase() || t.data!==data || (t.value??0n)!==0n || !t.gas || t.gas>approval.maxGas || t.maxFeePerGas===undefined || t.maxFeePerGas>approval.maxFeePerGas || (await recoverTransactionAddress({serializedTransaction:serialized})).toLowerCase()!==approval.relayer.toLowerCase())throw new Error('SIGNER_TRANSACTION_MISMATCH');
   return t;
  };
  const existing=await journal.read(key);
  if(existing && existing.intentHash!==intentHash)throw new Error('IDEMPOTENCY_CONFLICT');
  if(existing?.rawTransaction && existing.transactionHash) {
   await validateRaw(existing.rawTransaction);
   if(keccak256(existing.rawTransaction)!==existing.transactionHash)throw new Error('CORRUPT_JOURNAL');
   const hash=await this.client.sendRawTransaction({serializedTransaction:existing.rawTransaction});
   if(hash!==existing.transactionHash)throw new Error('TRANSACTION_HASH_MISMATCH');
   return {status:'BROADCAST',intentHash,transactionHash:hash};
  }
  if(existing || !await journal.reserve(key,intentHash))return {status:'NEEDS_RECONCILIATION',intentHash};
  await this.simulate(action,signature,approval.relayer);
  const tx:TransactionSerializableEIP1559={type:'eip1559',chainId,nonce:await journal.reserveNonce(chainId,approval.relayer,await this.client.getTransactionCount({address:approval.relayer,blockTag:'pending'})),to:this.address,data,value:0n,gas:approval.maxGas,maxFeePerGas:approval.maxFeePerGas,maxPriorityFeePerGas:0n};
  const raw=await signer.signTransaction(tx);const signed=await validateRaw(raw);
  if(signed.nonce!==tx.nonce || signed.gas!==tx.gas || signed.maxFeePerGas!==tx.maxFeePerGas || (signed.maxPriorityFeePerGas??0n)!==0n)throw new Error('SIGNER_TRANSACTION_MISMATCH');
  const hash=keccak256(raw);await journal.save(key,{intentHash,rawTransaction:raw,transactionHash:hash,status:'SIGNED'});
  const submitted=await this.client.sendRawTransaction({serializedTransaction:raw});if(submitted!==hash)throw new Error('TRANSACTION_HASH_MISMATCH');
  await journal.save(key,{intentHash,rawTransaction:raw,transactionHash:hash,status:'BROADCAST'});
  return {status:'BROADCAST',intentHash,transactionHash:hash};
 }
}
