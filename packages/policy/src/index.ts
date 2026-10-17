import { z } from 'zod';
import { hashTypedData, keccak256, toHex, type Address, type Hex } from 'viem';

export const PAY = 9 as const;
const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/).transform(x => x as Address);
const bytes32 = z.string().regex(/^0x[0-9a-fA-F]{64}$/).transform(x => x as Hex);
const u256 = z.bigint().min(0n).max((1n << 256n)-1n);
const u64 = z.bigint().min(0n).max((1n << 64n)-1n);
export const rootSchema = z.object({version:u64, token:address,recipient:address,adapterId:bytes32,recovery:address,perAction:u256,perPeriod:u256,total:u256,periodSeconds:u64,maxLeaseLifetime:u64}).strict();
export const leaseSchema = z.object({leaseId:bytes32,rootHash:bytes32,agent:address,validAfter:u64,expiresAt:u64,perAction:u256,perPeriod:u256,total:u256}).strict();
export const actionSchema = z.object({leaseId:bytes32,nonce:u256,kind:z.literal(PAY),token:address,recipient:address,adapterId:bytes32,amount:u256,deadline:u64,maxFee:z.literal(0n),feeRecipient:z.literal('0x0000000000000000000000000000000000000000'),planHash:bytes32}).strict();
export type RootPolicy = z.infer<typeof rootSchema>;
export type AgentLease = z.infer<typeof leaseSchema>;
export type ActionIntent = z.infer<typeof actionSchema>;
export const types = {
 RootPolicy:[{name:'version',type:'uint64'},{name:'token',type:'address'},{name:'recipient',type:'address'},{name:'adapterId',type:'bytes32'},{name:'recovery',type:'address'},{name:'perAction',type:'uint256'},{name:'perPeriod',type:'uint256'},{name:'total',type:'uint256'},{name:'periodSeconds',type:'uint64'},{name:'maxLeaseLifetime',type:'uint64'}],
 AgentLease:[{name:'leaseId',type:'bytes32'},{name:'rootHash',type:'bytes32'},{name:'agent',type:'address'},{name:'validAfter',type:'uint64'},{name:'expiresAt',type:'uint64'},{name:'perAction',type:'uint256'},{name:'perPeriod',type:'uint256'},{name:'total',type:'uint256'}],
 ActionIntent:[{name:'leaseId',type:'bytes32'},{name:'nonce',type:'uint256'},{name:'kind',type:'uint8'},{name:'token',type:'address'},{name:'recipient',type:'address'},{name:'adapterId',type:'bytes32'},{name:'amount',type:'uint256'},{name:'deadline',type:'uint64'},{name:'maxFee',type:'uint256'},{name:'feeRecipient',type:'address'},{name:'planHash',type:'bytes32'}],
 Control:[{name:'operation',type:'bytes32'},{name:'target',type:'address'},{name:'nonce',type:'uint256'},{name:'deadline',type:'uint64'}],
} as const;
export const typeHashes = Object.fromEntries(Object.entries(types).map(([name,fields])=>[name,keccak256(toHex(`${name}(${fields.map(f=>`${f.type} ${f.name}`).join(',')})`))])) as Record<keyof typeof types,Hex>;
export function domain(chainId:number,account:Address) {
 if(chainId!==5042002 && chainId!==31337) throw new Error('UNSUPPORTED_CHAIN');
 return {name:'Amane Arc',version:'2',chainId,verifyingContract:account} as const;
}
export function policyHash(policy:RootPolicy,chainId:number,account:Address):Hex {return hashTypedData({domain:domain(chainId,account),types,primaryType:'RootPolicy',message:policy});}
export function leaseHash(lease:AgentLease,chainId:number,account:Address):Hex {return hashTypedData({domain:domain(chainId,account),types,primaryType:'AgentLease',message:lease});}
export function actionHash(action:ActionIntent,chainId:number,account:Address):Hex {return hashTypedData({domain:domain(chainId,account),types,primaryType:'ActionIntent',message:action});}
export function controlHash(operation:Hex,target:Address,nonce:bigint,deadline:bigint,chainId:number,account:Address):Hex {return hashTypedData({domain:domain(chainId,account),types,primaryType:'Control',message:{operation,target,nonce,deadline}});}
function caps(p:{perAction:bigint;perPeriod:bigint;total:bigint}) {if(p.perAction===0n || p.perAction>p.perPeriod || p.perPeriod>p.total) throw new Error('INVALID_CAPS');}
const zero = '0x0000000000000000000000000000000000000000';
export function compilePolicy(input:unknown,chainId:number,account:Address):{policy:RootPolicy;rootHash:Hex;supportedClauseSet:readonly string[]} {
 const p=rootSchema.parse(input); domain(chainId,account); caps(p);
 if(p.version===0n || p.periodSeconds===0n || p.maxLeaseLifetime===0n || p.recipient.toLowerCase()===account.toLowerCase() || [p.token,p.recipient,p.recovery].some(x=>x.toLowerCase()===zero)) throw new Error('INVALID_POLICY');
 if(chainId===5042002 && p.token.toLowerCase()!=='0x3600000000000000000000000000000000000000') throw new Error('UNSUPPORTED_ASSET');
 return {policy:p,rootHash:policyHash(p,chainId,account),supportedClauseSet:['PAY','PINNED_RECIPIENT','PINNED_ADAPTER','FIXED_PERIOD_CAP','TOTAL_CAP','PAUSE','REVOCATION']};
}
export function validateLease(root:RootPolicy,rootHash:Hex,input:unknown):AgentLease {
 const l=leaseSchema.parse(input);caps(l);
 if(l.rootHash!==rootHash || l.leaseId===`0x${'00'.repeat(32)}` || l.agent.toLowerCase()===zero || l.expiresAt<=l.validAfter || l.expiresAt-l.validAfter>root.maxLeaseLifetime || l.perAction>root.perAction || l.perPeriod>root.perPeriod || l.total>root.total) throw new Error('REJECTED_LEASE');
 return l;
}
export interface ExecutionState {now:bigint;paused:boolean;revoked:boolean;nonceUsed:boolean;rootPeriodSpent:bigint;rootTotalSpent:bigint;leasePeriodSpent:bigint;leaseTotalSpent:bigint}
export function validateAction(root:RootPolicy,rootHash:Hex,lease:AgentLease,input:unknown,state:ExecutionState):ActionIntent {
 const a=actionSchema.parse(input);validateLease(root,rootHash,lease);
 if(state.paused || state.revoked || state.nonceUsed || state.now<lease.validAfter || state.now>lease.expiresAt || state.now>a.deadline) throw new Error('REJECTED_STATE');
 if(a.leaseId!==lease.leaseId || a.amount===0n || a.token.toLowerCase()!==root.token.toLowerCase() || a.recipient.toLowerCase()!==root.recipient.toLowerCase() || a.adapterId!==root.adapterId) throw new Error('REJECTED_SCOPE');
 if(a.amount>lease.perAction || a.amount>root.perAction || state.leasePeriodSpent+a.amount>lease.perPeriod || state.rootPeriodSpent+a.amount>root.perPeriod || state.leaseTotalSpent+a.amount>lease.total || state.rootTotalSpent+a.amount>root.total) throw new Error('REJECTED_BUDGET');
 return a;
}
export const capabilities = {
 status:'NOT_CONFIGURED',leaseAuthority:'ONCHAIN',actions:['PAY'],feeMode:'SPONSORED_NO_REIMBURSEMENT',crosschainIntentLevel:'VAULT_CUSTODY_OFFCHAIN_PROVENANCE',quotaLevel:'LOCAL_ACCOUNTING_ONLY',signerKinds:['EOA'],unsupported:['SWAP','BRIDGE','ESCROW_FUND','ERC1271','CIRCLE_MODULAR','SAFE_MODULE','ERC7579','SUI_V2','GLOBAL_QUOTA_ENFORCEMENT'],
} as const;
