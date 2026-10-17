import { getAddress, keccak256, parseAbi, toHex, type Address, type Hex, type PublicClient } from 'viem';
import { evmAdapterId, evmChainRef, type RootPolicy } from '@amane/core';
import { validateAuthorityPolicy, type AuthorityContext } from './authority.js';
const registryAbi=parseAbi(['function chainRef() view returns (bytes32)','function get(bytes32) view returns ((address adapter,uint8 actionKind,uint32 adapterVersion,bytes32 nameHash,bytes32 codeHash))']);
const tokenAbi=parseAbi(['function decimals() view returns (uint8)']);
const observation=Symbol('rpc-observation');
export interface AuthorityAssetIdentity {assetId:Hex;token:Address;decimals:number;codeHash:Hex}
export interface AuthorityRegistryRequest {registry:Address;registryCodeHash:Hex;assets:AuthorityAssetIdentity[]}
/** RPC-authenticated observation, not a consensus/light-client proof. Immutable policy + block are bound together. */
export interface ResolvedAuthorityPolicy {readonly policy:RootPolicy;readonly chainId:number;readonly account:Address;readonly blockNumber:bigint;readonly blockHash:Hex;readonly registry:Address;readonly registryCodeHash:Hex;readonly proofLevel:'RPC_CODE_IDENTITY';readonly [observation]:true}
const issued=new WeakSet<object>();
export async function compileAuthorityPolicy(client:PublicClient,input:unknown,ctx:AuthorityContext,request:AuthorityRegistryRequest):Promise<ResolvedAuthorityPolicy> {
  const policy=validateAuthorityPolicy(input,ctx);
  if(await client.getChainId()!==ctx.chainId)throw Error('RPC_CHAIN_MISMATCH');
  const block=await client.getBlock();if(block.number===null||block.hash===null)throw Error('UNMINED_BLOCK');
  const blockNumber=block.number;
  const registryCode=await client.getCode({address:request.registry,blockNumber});
  if(!registryCode||registryCode==='0x'||keccak256(registryCode)!==request.registryCodeHash)throw Error('REGISTRY_CODE_MISMATCH');
  const chainRef=evmChainRef(ctx.chainId);
  if((await client.readContract({address:request.registry,abi:registryAbi,functionName:'chainRef',blockNumber})).toLowerCase()!==chainRef.toLowerCase())throw Error('REGISTRY_CHAIN_MISMATCH');
  const own=policy.endpoints.find(e=>e.chainRef.toLowerCase()===chainRef.toLowerCase()&&getAddress(`0x${e.account.slice(-40)}`)===getAddress(ctx.account))!;
  for(const ref of own.adapters) {
    const entry=await client.readContract({address:request.registry,abi:registryAbi,functionName:'get',args:[ref.adapterId],blockNumber});
    const code=await client.getCode({address:entry.adapter,blockNumber});
    if(!code||code==='0x'||keccak256(code)!==entry.codeHash)throw Error('ADAPTER_CODE_MISMATCH');
    if(entry.nameHash!==keccak256(toHex(ref.adapterName))||entry.adapterVersion!==ref.adapterVersion)throw Error('ADAPTER_METADATA_MISMATCH');
    if(![0,9,10,11].includes(entry.actionKind)||(policy.allowedActions&(1<<entry.actionKind))===0)throw Error('ADAPTER_KIND_MISMATCH');
    if(evmAdapterId({chainRef,actionKind:entry.actionKind,adapterVersion:entry.adapterVersion,adapterName:ref.adapterName,adapter:entry.adapter,codeHash:entry.codeHash}).toLowerCase()!==ref.adapterId.toLowerCase())throw Error('ADAPTER_ID_MISMATCH');
  }
  for(const asset of own.assets) {
    if(!/^0x0{24}[0-9a-fA-F]{40}$/.test(asset.assetId))throw Error('NON_EVM_ASSET');
    const identity=request.assets.find(x=>x.assetId.toLowerCase()===asset.assetId.toLowerCase());
    if(!identity||getAddress(identity.token)!==getAddress(`0x${asset.assetId.slice(-40)}`))throw Error('MISSING_ASSET_IDENTITY');
    const code=await client.getCode({address:identity.token,blockNumber});
    if(!code||code==='0x'||keccak256(code)!==identity.codeHash)throw Error('ASSET_CODE_MISMATCH');
    const decimals=await client.readContract({address:identity.token,abi:tokenAbi,functionName:'decimals',blockNumber});
    if(decimals!==identity.decimals)throw Error('ASSET_DECIMAL_MISMATCH');
    if(ctx.chainId===5042002&&getAddress(identity.token)===getAddress('0x3600000000000000000000000000000000000000')&&decimals!==6)throw Error('ARC_ERC20_USDC_DECIMALS');
  }
  const canonical=await client.getBlock({blockNumber});if(canonical.hash!==block.hash)throw Error('RPC_REORG');
  const result={policy,chainId:ctx.chainId,account:getAddress(ctx.account),blockNumber,blockHash:block.hash,registry:request.registry,registryCodeHash:request.registryCodeHash,proofLevel:'RPC_CODE_IDENTITY' as const,[observation]:true as const};
  // Recursively freeze so an asynchronously resolved policy cannot be edited after identity checks.
  const freeze=(x:unknown):void=>{if(x&&typeof x==='object'){for(const v of Object.values(x))freeze(v);Object.freeze(x);}};freeze(result);issued.add(result);return result;
}
export function assertResolvedAuthorityPolicy(value:ResolvedAuthorityPolicy):void {if(!issued.has(value))throw Error('UNRESOLVED_AUTHORITY_POLICY');}
