import { encodeFunctionData, encodeAbiParameters, keccak256, toHex, type Address, type Hex } from 'viem';
// Observed in Circle's official testnet contract address documentation. Must be runtime verified.
export const CCTP_TESTNET = {sourceChainId:11155111,sourceDomain:0,destinationChainId:5042002,destinationDomain:26,tokenMessengerV2:'0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA' as Address,messageTransmitterV2:'0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275' as Address,usdc:'0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' as Address} as const;
export interface SourceCommitment {sourceChainId:11155111;destinationChainId:5042002;sourceSender:Address;vault:Address;amount:bigint;maxFee:bigint;minArrival:bigint;deadline:bigint;destinationActionHash:Hex;recoveryPolicyHash:Hex}
export const burnAbi=[{type:'function',name:'depositForBurnWithHook',stateMutability:'nonpayable',inputs:[{name:'amount',type:'uint256'},{name:'destinationDomain',type:'uint32'},{name:'mintRecipient',type:'bytes32'},{name:'burnToken',type:'address'},{name:'destinationCaller',type:'bytes32'},{name:'maxFee',type:'uint256'},{name:'minFinalityThreshold',type:'uint32'},{name:'hookData',type:'bytes'}],outputs:[]}] as const;
export function commitmentHash(c:SourceCommitment):Hex {
 if(c.sourceChainId!==11155111 || c.destinationChainId!==5042002 || c.amount<=0n || c.maxFee<0n || c.maxFee>=c.amount || c.minArrival<=0n || c.minArrival>c.amount-c.maxFee || c.deadline<=0n || !/^0x[0-9a-fA-F]{40}$/.test(c.vault) || BigInt(c.vault)===0n)throw new Error('UNSUPPORTED_OR_INVALID_ROUTE');
 // Diagnostic canonical commitment, not an on-chain authorization or Circle attestation.
 return keccak256(encodeAbiParameters([{type:'bytes32'},{type:'uint256'},{type:'uint256'},{type:'address'},{type:'address'},{type:'uint256'},{type:'uint256'},{type:'uint256'},{type:'uint64'},{type:'bytes32'},{type:'bytes32'}],[keccak256(toHex('AMANE_CCTP_SOURCE_V2')),BigInt(c.sourceChainId),BigInt(c.destinationChainId),c.sourceSender,c.vault,c.amount,c.maxFee,c.minArrival,c.deadline,c.destinationActionHash,c.recoveryPolicyHash]));
}
export function prepareBurn(c:SourceCommitment,now:bigint) {
 const hash=commitmentHash(c);if(now>c.deadline)throw new Error('EXPIRED');
 const mintRecipient=`0x${c.vault.slice(2).padStart(64,'0')}` as Hex;
 return {chainId:11155111,to:CCTP_TESTNET.tokenMessengerV2,value:0n,data:encodeFunctionData({abi:burnAbi,functionName:'depositForBurnWithHook',args:[c.amount,26,mintRecipient,CCTP_TESTNET.usdc,`0x${'00'.repeat(32)}`,c.maxFee,2000,hash]}),commitmentHash:hash,proofLevel:'UNAVAILABLE' as const,requiresHumanSignature:true,warning:'Preparation only. Root/lease-authorized BRIDGE adapter is unavailable; do not label this bounded Amane bridge execution.'};
}
export const arrivalStates=['SOURCE_COMMITTED','BURN_BROADCAST','BURN_FINAL','ATTESTED','DEST_MINT','DEST_RESERVED','DEST_EXECUTED','QUARANTINED','ROOT_RECOVERED'] as const;
export type ArrivalState=typeof arrivalStates[number];
export function advanceArrival(current:ArrivalState,next:ArrivalState):ArrivalState {
 if(current===next)return current;
 const edges:Record<ArrivalState,readonly ArrivalState[]>={SOURCE_COMMITTED:['BURN_BROADCAST'],BURN_BROADCAST:['BURN_FINAL'],BURN_FINAL:['ATTESTED'],ATTESTED:['DEST_MINT'],DEST_MINT:['DEST_RESERVED','QUARANTINED'],DEST_RESERVED:['DEST_EXECUTED','QUARANTINED'],DEST_EXECUTED:[],QUARANTINED:['ROOT_RECOVERED'],ROOT_RECOVERED:[]};
 if(!edges[current].includes(next))throw new Error('INVALID_TRANSITION');return next;
}
export function authenticatedIntentLevel(_attestationJson:unknown):'UNAVAILABLE' {return 'UNAVAILABLE';}
