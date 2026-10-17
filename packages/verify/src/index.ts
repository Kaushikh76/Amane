import {decodeEventLog,keccak256,type Address,type Hex,type PublicClient,type TransactionReceipt} from 'viem';
import {actionHash,type ActionIntent} from '@amane/policy';
const event=[{type:'event',name:'Executed',inputs:[{name:'digest',type:'bytes32',indexed:true},{name:'leaseId',type:'bytes32',indexed:true},{name:'nonce',type:'uint256',indexed:false},{name:'token',type:'address',indexed:false},{name:'recipient',type:'address',indexed:false},{name:'amount',type:'uint256',indexed:false},{name:'fee',type:'uint256',indexed:false}]}] as const;
export function validateReceiptShape(receipt:TransactionReceipt,chainId:number,account:Address,intent:ActionIntent,expectedTransactionHash:Hex) {
 if(chainId!==5042002 && chainId!==31337)throw new Error('UNSUPPORTED_CHAIN');
 if(receipt.transactionHash!==expectedTransactionHash || receipt.status!=='success' || receipt.to?.toLowerCase()!==account.toLowerCase())throw new Error('INVALID_RECEIPT');
 const expected=actionHash(intent,chainId,account);
 const effects=receipt.logs.filter(x=>x.address.toLowerCase()===account.toLowerCase()).flatMap(log=>{try{return [decodeEventLog({abi:event,data:log.data,topics:log.topics})];}catch{return [];}});
 const matches=effects.filter(e=>e.args.digest===expected && e.args.leaseId===intent.leaseId && e.args.nonce===intent.nonce && e.args.token.toLowerCase()===intent.token.toLowerCase() && e.args.recipient.toLowerCase()===intent.recipient.toLowerCase() && e.args.amount===intent.amount && e.args.fee===0n);
 if(matches.length!==1 || effects.length!==1)throw new Error('EVENT_MISMATCH');
 // Count the custody contract's measured execution once, never native/ERC20 mirror logs separately.
 return {status:'UNAUTHENTICATED_RECEIPT_MATCH',proofLevel:'NOT_VERIFIED',intentHash:expected,amountBaseUnits:intent.amount,transactionHash:receipt.transactionHash} as const;
}
export async function verifyExecution(client:PublicClient,account:Address,expectedCodeHash:Hex,intent:ActionIntent,hash:Hex) {
 const chainId=await client.getChainId();const receipt=await client.getTransactionReceipt({hash});
 const [code,block]=await Promise.all([client.getCode({address:account,blockNumber:receipt.blockNumber}),client.getBlock({blockNumber:receipt.blockNumber})]);
 if(!code || keccak256(code)!==expectedCodeHash || block.hash!==receipt.blockHash)throw new Error('CODE_OR_CANONICAL_BLOCK_MISMATCH');
 return {...validateReceiptShape(receipt,chainId,account,intent,hash),status:'CONTRACT_EVENT_VERIFIED' as const,proofLevel:chainId===31337?'LOCAL_INTEGRATION' as const:'ARC_TESTNET_RECEIPT_OBSERVED' as const,codeHash:expectedCodeHash,blockHash:receipt.blockHash,finality:'NOT_ESTABLISHED' as const};
}
