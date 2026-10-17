import { decodeAbiParameters,encodeAbiParameters,hexToBigInt,keccak256,sliceHex,toHex,type Address,type Hex } from 'viem';
export const AUTHORITY_HOOK_TAG=keccak256(toHex('AMANE_CCTP_AUTHORITY_V3_HOOK'));
export function authorityHook(sourceAccount:Address,destinationAccount:Address,intent:Hex,destinationSpecHash:Hex):Hex {return encodeAbiParameters([{type:'bytes32'},{type:'address'},{type:'address'},{type:'bytes32'},{type:'bytes32'}],[AUTHORITY_HOOK_TAG,sourceAccount,destinationAccount,intent,destinationSpecHash]);}
/** Decode untrusted raw bytes for inspection. Authentication happens only inside the pinned receiving vault. */
export function inspectAuthorityBurn(message:Hex){
 if(!/^0x([0-9a-fA-F]{2})*$/.test(message)||(message.length-2)/2!==536)throw Error('INVALID_MESSAGE_LENGTH');
 const n=(start:number,length=32)=>hexToBigInt(sliceHex(message,start,start+length));const word=(start:number)=>sliceHex(message,start,start+32);
 if(n(0,4)!==1n||n(148,4)!==1n||n(144,4)<2000n)throw Error('INVALID_MESSAGE_VERSION_OR_FINALITY');
 const [tag,sourceAccount,destinationAccount,intent,destinationSpecHash]=decodeAbiParameters([{type:'bytes32'},{type:'address'},{type:'address'},{type:'bytes32'},{type:'bytes32'}],sliceHex(message,376));
 if(tag!==AUTHORITY_HOOK_TAG)throw Error('INVALID_HOOK');
 const amount=n(216),maxFee=n(280),fee=n(312);if(amount===0n||fee>maxFee||fee>=amount)throw Error('INVALID_FEE');
 return {sourceDomain:Number(n(4,4)),destinationDomain:Number(n(8,4)),nonce:word(12),sender:word(44),recipient:word(76),destinationCaller:word(108),finality:Number(n(144,4)),burnToken:word(152),mintRecipient:word(184),amount,messageSender:word(248),maxFee,fee,sourceAccount,destinationAccount,intent,destinationSpecHash,proofLevel:'UNAUTHENTICATED_BYTES' as const};
}
export function encodeAuthorityRedemption(message:Hex,attestation:Hex):Hex {inspectAuthorityBurn(message);if(!/^0x([0-9a-fA-F]{130})+$/.test(attestation))throw Error('INVALID_ATTESTATION_ENCODING');return encodeAbiParameters([{type:'bytes'},{type:'bytes'}],[message,attestation]);}
export interface CctpAttestationObservation {message:Hex;attestation:Hex;status:string;proofLevel:'OFFCHAIN_PROVIDER_RESPONSE'}
/** A fetched response remains untrusted until MessageTransmitter verifies it on chain. */
export async function fetchAuthorityAttestations(sourceTransactionHash:Hex,signal?:AbortSignal):Promise<CctpAttestationObservation[]> {
 if(!/^0x[0-9a-fA-F]{64}$/.test(sourceTransactionHash))throw Error('INVALID_TRANSACTION_HASH');
 const response=await fetch(`https://iris-api-sandbox.circle.com/v2/messages/0?transactionHash=${sourceTransactionHash}`,{signal});if(!response.ok)throw Error(`ATTESTATION_HTTP_${response.status}`);
 const payload:unknown=await response.json();if(!payload||typeof payload!=='object'||!('messages' in payload)||!Array.isArray(payload.messages))throw Error('INVALID_PROVIDER_RESPONSE');
 return payload.messages.map((entry:unknown)=>{if(!entry||typeof entry!=='object')throw Error('INVALID_PROVIDER_MESSAGE');const e=entry as Record<string,unknown>;if(typeof e.message!=='string'||typeof e.attestation!=='string'||typeof e.status!=='string')throw Error('INVALID_PROVIDER_MESSAGE');return {message:e.message as Hex,attestation:e.attestation as Hex,status:e.status,proofLevel:'OFFCHAIN_PROVIDER_RESPONSE' as const};});
}
