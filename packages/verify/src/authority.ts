import {decodeFunctionData,decodeEventLog,encodeAbiParameters,keccak256,getAddress,type Hex,type PublicClient} from 'viem';
import {authorityArtifacts,type AuthorityDeployment} from '@amane/arc/authority';
import {type ActionIntent} from '@amane/core';
const abi=authorityArtifacts.ArcAuthority.abi;
const actionParameter=abi.find(x=>'name' in x&&x.name==='executeAction'&&x.type==='function')!.inputs[0];
/** Verify fetched canonical execution against exact calldata and pinned historical code identity. */
export async function verifyAuthorityExecution(client:PublicClient,deployment:AuthorityDeployment,hash:Hex,action:ActionIntent,confirmations=1){
 if(!Number.isSafeInteger(confirmations)||confirmations<1)throw Error('INVALID_CONFIRMATIONS');
 if(await client.getChainId()!==deployment.chainId)throw Error('CHAIN_MISMATCH');
 const [tx,receipt]=await Promise.all([client.getTransaction({hash}),client.getTransactionReceipt({hash})]);
 if(receipt.status!=='success'||!tx.to||getAddress(tx.to)!==getAddress(deployment.account)||tx.blockHash!==receipt.blockHash)throw Error('EXECUTION_NOT_SUCCESSFUL');
 const canonical=await client.getBlock({blockNumber:receipt.blockNumber});if(canonical.hash!==receipt.blockHash)throw Error('NONCANONICAL_RECEIPT');
 const latest=await client.getBlockNumber({cacheTime:0});if(latest<receipt.blockNumber+BigInt(confirmations-1))throw Error('INSUFFICIENT_CONFIRMATIONS');
 for(const [address,expected] of [[deployment.account,deployment.accountCodeHash],[deployment.extension,deployment.extensionCodeHash]] as const){const code=await client.getCode({address,blockNumber:receipt.blockNumber});if(!code||code==='0x'||keccak256(code)!==expected)throw Error('HISTORICAL_CODE_MISMATCH');}
 const ext=await client.readContract({address:deployment.account,abi,functionName:'ext',blockNumber:receipt.blockNumber});if(getAddress(ext)!==getAddress(deployment.extension))throw Error('EXTENSION_MISMATCH');
 const decoded=decodeFunctionData({abi,data:tx.input});if(decoded.functionName!=='executeAction'&&decoded.functionName!=='executeActionWithFee')throw Error('UNSUPPORTED_EXECUTION_PATH');
 const actual=decoded.args[0];if(keccak256(encodeAbiParameters([actionParameter as never],[actual] as never))!==keccak256(encodeAbiParameters([actionParameter as never],[action] as never)))throw Error('ACTION_CALLDATA_MISMATCH');
 const events=receipt.logs.filter(log=>getAddress(log.address)===getAddress(deployment.account)).flatMap(log=>{try{const event=decodeEventLog({abi,eventName:'ActionExecuted',data:log.data,topics:log.topics});return [event];}catch{return [];}});
 if(events.length!==1)throw Error('EXECUTION_EVENT_MISMATCH');const e=events[0]!.args;
 if(e.leaseId!==action.leaseId||e.nonce!==action.nonce||e.adapterId!==action.adapterId||e.actionKind!==action.actionKind||e.amountIn!==action.amountIn||e.planHash!==action.planHash||e.planStep!==action.planStep)throw Error('EXECUTION_EVENT_MISMATCH');
 return {status:'VERIFIED_EXECUTION' as const,proofLevel:'RPC_CANONICAL_RECEIPT_CODE_IDENTITY' as const,transactionHash:hash,blockHash:receipt.blockHash,blockNumber:receipt.blockNumber,confirmations:Number(latest-receipt.blockNumber+1n),amountOut:e.amountOut,finality:'CONFIRMATIONS_ONLY' as const,globalQuota:'NOT_INFERRED' as const};
}
