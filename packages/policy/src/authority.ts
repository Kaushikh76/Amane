/** Version 3 full authority candidate. Separate subpath: no change to the deployed v2 API. */
import { z } from 'zod';
import { getAddress, hashTypedData, type Address } from 'viem';
import { AMANE_TYPES, assertPolicyWellFormed, assertLeaseIsSubset, assertActionIsSubset, addressToBytes32, evmChainRef, type RootPolicy, type AgentLease, type ActionIntent, type AmanePrimaryType, type AmaneMessageMap } from '@amane/core';

const b32 = z.string().regex(/^0x[0-9a-fA-F]{64}$/).transform(x => x as `0x${string}`);
const addr = z.string().regex(/^0x[0-9a-fA-F]{40}$/).transform(x => getAddress(x));
const uint = (bits: number) => z.bigint().min(0n).max((1n << BigInt(bits))-1n);
const u64=uint(64),u256=uint(256);
const u32=z.number().int().min(0).max(0xffffffff);
const label=z.string().min(1).max(256);
const capFields={maxPerAction:u256,maxPerEpoch:u256,maxTotal:u256};
const monotone=(x:{maxPerAction:bigint;maxPerEpoch:bigint;maxTotal:bigint}) => x.maxPerAction<=x.maxPerEpoch&&x.maxPerEpoch<=x.maxTotal;
const asset=z.object({assetId:b32,...capFields}).strict().refine(monotone,'CAP_ORDER');
const recipient=z.object({recipientId:b32,label}).strict();
const adapter=z.object({adapterId:b32,adapterName:label,adapterVersion:u32}).strict();
const endpoint=z.object({chainRef:b32,account:b32,epochSeconds:u64.refine(x=>x>0n),adapters:z.array(adapter),assets:z.array(asset),recipients:z.array(recipient),beneficiaries:z.array(recipient),swapFloors:z.array(z.object({assetIn:b32,assetOut:b32,minOutNumerator:u256.refine(x=>x>0n),minOutDenominator:u256.refine(x=>x>0n)}).strict()),recoveryDestinations:z.array(recipient).min(1)}).strict();
const issuerLimit=z.object({chainRef:b32,assetId:b32,...capFields}).strict().refine(monotone,'CAP_ORDER');
export const authorityPolicySchema=z.object({accountId:b32,policyVersion:u64.refine(x=>x>0n),parentPolicyHash:b32,allowedActions:u32,priceMode:z.literal(1),maxLeaseLifetime:u64.refine(x=>x>0n),activateBefore:u64,endpoints:z.array(endpoint).min(1),leaseIssuers:z.array(z.object({issuer:addr,maxLeaseLifetime:u64.refine(x=>x>0n),allowedAgents:z.array(addr).min(1),limits:z.array(issuerLimit)}).strict())}).strict();
export const authorityLeaseSchema=z.object({accountId:b32,policyVersion:u64,leaseId:b32,agent:addr,issuer:addr,validAfter:u64,expiresAt:u64,activateBefore:u64,allowedActions:u32,authMode:z.literal(1),endpoints:z.array(z.object({chainRef:b32,account:b32,adapters:z.array(b32),assets:z.array(asset),recipients:z.array(b32),beneficiaries:z.array(b32)}).strict()).min(1)}).strict();
export const authorityActionSchema=z.object({accountId:b32,chainRef:b32,account:b32,policyVersion:u64,leaseId:b32,nonce:u64,actionKind:z.union([z.literal(0),z.literal(9),z.literal(10),z.literal(11)]),adapterId:b32,adapterName:label,adapterVersion:u32,assetIn:b32,assetOut:b32,amountIn:u256.refine(x=>x>0n),minAmountOut:u256,recipient:b32,recipientLabel:z.string().max(256),deadline:u64,planHash:b32,planStep:u32}).strict();
export const AUTHORITY_SUPPORTED_MASK=(1<<0)|(1<<9)|(1<<10)|(1<<11);
export function authorityDomain(chainId:number,account:Address) {
  if(![5042002,11155111,31337].includes(chainId))throw Error('UNSUPPORTED_AUTHORITY_CHAIN');
  return {name:'Amane Arc',version:'3',chainId,verifyingContract:getAddress(account)} as const;
}
export function authorityTypedData<P extends AmanePrimaryType>(chainId:number,account:Address,primaryType:P,message:AmaneMessageMap[P]) {
  return {domain:authorityDomain(chainId,account),types:AMANE_TYPES,primaryType,message} as const;
}
export function authorityDigest<P extends AmanePrimaryType>(chainId:number,account:Address,primaryType:P,message:AmaneMessageMap[P]) {
  return hashTypedData(authorityTypedData(chainId,account,primaryType,message) as never);
}
function unique(values:string[]) { if(new Set(values.map(x=>x.toLowerCase())).size!==values.length)throw Error('DUPLICATE_ENTRY'); }
function mask(n:number) {if((n&AUTHORITY_SUPPORTED_MASK)!==n)throw Error('UNSUPPORTED_ACTION');}
export interface AuthorityContext {chainId:number;account:Address;controllers:Address[];now:bigint;currentPolicyHash?:`0x${string}`;currentVersion?:bigint}
function context(c:AuthorityContext) {authorityDomain(c.chainId,c.account);return {...c,chainRef:evmChainRef(c.chainId),account:addressToBytes32(c.account)};}
/** Strict structure/subset validation only. Registry identity resolution is a separate mandatory build step. */
export function validateAuthorityPolicy(input:unknown,c:AuthorityContext):RootPolicy {
  const p:RootPolicy=authorityPolicySchema.parse(input);mask(p.allowedActions);const ctx=context(c);
  unique(p.endpoints.map(e=>`${e.chainRef}:${e.account}`));
  for(const e of p.endpoints) {
    // Validate every endpoint, including those the selected EVM cannot execute.
    assertPolicyWellFormed(p,{...ctx,chainRef:e.chainRef,account:e.account});
    for(const i of p.leaseIssuers) {
      unique(i.allowedAgents);unique(i.limits.map(l=>`${l.chainRef}:${l.assetId}`));
      for(const l of i.limits.filter(l=>l.chainRef.toLowerCase()===e.chainRef.toLowerCase())) {
        const root=e.assets.find(a=>a.assetId.toLowerCase()===l.assetId.toLowerCase());
        if(!root||l.maxPerAction>root.maxPerAction||l.maxPerEpoch>root.maxPerEpoch||l.maxTotal>root.maxTotal)throw Error('ISSUER_CAP_EXCEEDS_ROOT');
      }
    }
  }
  assertPolicyWellFormed(p,ctx);return p;
}
export function validateAuthorityLease(policy:RootPolicy,input:unknown,c:AuthorityContext):AgentLease {
  const l:AgentLease=authorityLeaseSchema.parse(input);mask(l.allowedActions);unique(l.endpoints.map(e=>`${e.chainRef}:${e.account}`));
  for(const e of l.endpoints)assertLeaseIsSubset(policy,l,{...context(c),chainRef:e.chainRef,account:e.account});
  assertLeaseIsSubset(policy,l,context(c));return l;
}
export function validateAuthorityAction(p:RootPolicy,l:AgentLease,input:unknown,c:AuthorityContext):{action:ActionIntent;effectiveMinOut:bigint} {
  const action:ActionIntent=authorityActionSchema.parse(input);
  if(l.policyVersion!==p.policyVersion)throw Error('POLICY_VERSION_MISMATCH');
  if((p.allowedActions&(1<<action.actionKind))===0)throw Error('ACTION_KIND_NOT_ALLOWED');
  if(action.actionKind===10 && (!p.endpoints.some(e=>e.account.toLowerCase()===action.recipient.toLowerCase()) || action.recipient.toLowerCase()===action.account.toLowerCase()))throw Error('BRIDGE_DESTINATION_NOT_ENDPOINT');
  // ESCROW_FUND has exactly PAY's pinned recipient and same-asset transfer semantics.
  const mirror=action.actionKind===11?{...action,actionKind:9}:action;
  const lease=action.actionKind===11?{...l,allowedActions:l.allowedActions|(1<<9)}:l;
  if((l.allowedActions&(1<<action.actionKind))===0)throw Error('ACTION_KIND_NOT_ALLOWED');
  const minimum=assertActionIsSubset(p,lease,mirror,context(c));
  return {action,effectiveMinOut:action.actionKind===9||action.actionKind===11?action.amountIn:minimum};
}
export type { RootPolicy,AgentLease,ActionIntent } from '@amane/core';
