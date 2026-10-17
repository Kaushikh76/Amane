import {hashTypedData,type Address,type Hex} from 'viem';
import {authorityDomain} from './authority.js';
export interface AuthorityFeePolicy {rootHash:Hex;leaseId:Hex;token:Address;recipient:Address;perAction:bigint;perPeriod:bigint;total:bigint;periodSeconds:bigint;maxGasUnits:bigint;maxGasPrice:bigint;nonce:bigint;deadline:bigint}
export interface AuthorityFeeIntent {actionDigest:Hex;feePolicyHash:Hex;amount:bigint}
export interface AuthorityQuotaBinding {policyHash:Hex;localAsset:Hex;budgetAsset:Hex;leaf:Address;grantId:Hex;nonce:bigint;deadline:bigint}
export interface AuthorityQuotaGrant {policyHash:Hex;asset:Hex;endpointChain:Hex;endpoint:Address;epoch:bigint;nonce:bigint;expiresAt:bigint;amount:bigint}
export const AUTHORITY_CONTROL_TYPES={
 FeePolicy:[{name:'rootHash',type:'bytes32'},{name:'leaseId',type:'bytes32'},{name:'token',type:'address'},{name:'recipient',type:'address'},{name:'perAction',type:'uint256'},{name:'perPeriod',type:'uint256'},{name:'total',type:'uint256'},{name:'periodSeconds',type:'uint64'},{name:'maxGasUnits',type:'uint256'},{name:'maxGasPrice',type:'uint256'},{name:'nonce',type:'uint64'},{name:'deadline',type:'uint64'}],
 FeeIntent:[{name:'actionDigest',type:'bytes32'},{name:'feePolicyHash',type:'bytes32'},{name:'amount',type:'uint256'}],
 BindQuota:[{name:'policyHash',type:'bytes32'},{name:'localAsset',type:'bytes32'},{name:'budgetAsset',type:'bytes32'},{name:'leaf',type:'address'},{name:'grantId',type:'bytes32'},{name:'nonce',type:'uint64'},{name:'deadline',type:'uint64'}],
} as const;
export function authorityControlTypedData<K extends keyof typeof AUTHORITY_CONTROL_TYPES>(chainId:number,account:Address,primaryType:K,message:K extends 'FeePolicy'?AuthorityFeePolicy:K extends 'FeeIntent'?AuthorityFeeIntent:AuthorityQuotaBinding){return {domain:authorityDomain(chainId,account),types:AUTHORITY_CONTROL_TYPES,primaryType,message} as const;}
export function authorityControlDigest<K extends keyof typeof AUTHORITY_CONTROL_TYPES>(chainId:number,account:Address,primaryType:K,message:K extends 'FeePolicy'?AuthorityFeePolicy:K extends 'FeeIntent'?AuthorityFeeIntent:AuthorityQuotaBinding){return hashTypedData(authorityControlTypedData(chainId,account,primaryType,message) as never);}
