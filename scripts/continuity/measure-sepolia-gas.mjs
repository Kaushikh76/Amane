// Local-only gas measurement for the remaining Sepolia authority steps.
// Talks ONLY to a local anvil (default http://127.0.0.1:8545, chain id 11155111) using anvil's public
// well-known dev key. No real key is read, no public network is contacted, nothing is broadcast.
// Start: anvil --chain-id 11155111 --hardfork cancun --gas-limit 100000000 --code-size-limit 24576
import {createPublicClient,createWalletClient,http,encodeDeployData,encodeFunctionData,keccak256,parseAbi,getContractAddress} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {artifacts} from '@amane/arc';import {authorityArtifacts} from '@amane/arc/authority';
import {authorityTypedData} from '@amane/policy/authority';
import {addressToBytes32,evmChainRef,ZERO32,amaneStructHash,destSpecHash} from '@amane/core';
const rpc=process.env.ANVIL_RPC??'http://127.0.0.1:8545';
if(!/^http:\/\/(127\.0\.0\.1|localhost)[:/]/.test(rpc))throw Error('LOCAL_ANVIL_ONLY');
const DEV_KEY='0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // anvil account 0, public
const owner=privateKeyToAccount(DEV_KEY),agent=privateKeyToAccount('0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');
const pub=createPublicClient({transport:http(rpc)});const wal=createWalletClient({account:owner,transport:http(rpc)});
const chainId=await pub.getChainId();if(chainId!==11155111)throw Error('RUN_ANVIL_WITH_CHAIN_ID_11155111');
const all={...artifacts,...authorityArtifacts};
const stub='0x60205ff3'; // returns 32 zero bytes: localDomain()==0 (Sepolia), non-empty code
const token='0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',messenger='0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA',transmitter='0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275';
for(const a of [token,messenger,transmitter])await pub.request({method:'anvil_setCode',params:[a,stub]});
const rows=[];
// New state created by a transaction (for the repricing model), from anvil state dumps before/after.
import {gunzipSync} from 'node:zlib';
const dump=async()=>{const hex=await pub.request({method:'anvil_dumpState',params:[]});const j=JSON.parse(gunzipSync(Buffer.from(hex.slice(2),'hex')).toString());return j.accounts??j;};
let before=await dump();
const zero=v=>v===undefined||/^0x0*$/.test(v);
async function stateGrowth(){
 const after=await dump();let newSlots=0,newAccounts=0,codeBytes=0;
 for(const [addr,acc] of Object.entries(after)){
  const was=before[addr];
  if(acc.code&&acc.code!=='0x'&&(!was||!was.code||was.code==='0x')){newAccounts++;codeBytes+=(acc.code.length-2)/2;}
  for(const [slot,val] of Object.entries(acc.storage??{}))if(zero(was?.storage?.[slot])&&!zero(val))newSlots++;
 }
 before=after;return {newAccounts,codeBytes,newSlots};
}
async function send(label,{to,data}){
 const est=await pub.estimateGas({account:owner.address,to,data});
 const hash=await wal.sendTransaction({to,data,gas:60000000n,chain:null});
 const r=await pub.waitForTransactionReceipt({hash});if(r.status!=='success')throw Error('FAILED_'+label);
 const g=await stateGrowth();rows.push({label,initcodeOrCalldataBytes:(data.length-2)/2,estimateGas:String(est),estimateX1_2Plus10000:String(est*12n/10n+10000n),gasUsed:String(r.gasUsed),...g});return r;
}
async function deploy(label,name,args=[]){const r=await send('deploy-'+label,{data:encodeDeployData({abi:all[name].abi,bytecode:all[name].bytecode,args})});return r.contractAddress;}
const call=(label,to,name,fn,args)=>send(label,{to,data:encodeFunctionData({abi:all[name].abi,functionName:fn,args})});
const registry=await deploy('AdapterRegistry','AdapterRegistry');
const ext=await deploy('ArcAuthorityExt','ArcAuthorityExt');
const factory=await deploy('ArcAuthorityFactory','ArcAuthorityFactory',[registry,ext]);
const accountId=keccak256(new TextEncoder().encode('measure')),salt=keccak256(new TextEncoder().encode('salt'));
const account=await pub.readContract({address:factory,abi:all.ArcAuthorityFactory.abi,functionName:'predict',args:[accountId,[owner.address],1,salt]});
await call('create-account',factory,'ArcAuthorityFactory','create',[accountId,[owner.address],1,salt]);
const arcAccount='0x00000000000000000000000000000000000a4c01',vault='0x00000000000000000000000000000000000a4c02';
const destSpec={actionKind:9,adapterId:keccak256('0x01'),recipient:addressToBytes32('0x263174780015983489C0987e4AB1886e7Ab8348E'),recipientLabel:'r',asset:addressToBytes32('0x3600000000000000000000000000000000000000'),minArrival:19900n,deadline:9999999999n};
const bridge=await deploy('CctpSourceAdapter','CctpSourceAdapter',[account,token,messenger,arcAccount,vault,100n,19900n,destSpecHash(destSpec)]);
const reg=await call('register-source',registry,'AdapterRegistry','register',[bridge]);
const logs=await pub.getLogs({address:registry,fromBlock:reg.blockNumber,toBlock:reg.blockNumber});
const bridgeId=logs.map(l=>l.topics[1]).find(Boolean);
const now=BigInt((await pub.getBlock()).timestamp),deadline=now+7200n;
const ep=(chain,acct,adapters,recips)=>({chainRef:evmChainRef(chain),account:addressToBytes32(acct),epochSeconds:86400n,adapters,assets:[{assetId:addressToBytes32(token),maxPerAction:25000n,maxPerEpoch:80000n,maxTotal:100000n}],recipients:recips,beneficiaries:[],swapFloors:[],recoveryDestinations:[{recipientId:addressToBytes32(owner.address),label:'Owner recovery'}]});
const policy={accountId,policyVersion:1n,parentPolicyHash:ZERO32,allowedActions:(1<<9)|(1<<10),priceMode:1,maxLeaseLifetime:7200n,activateBefore:deadline,endpoints:[ep(11155111,account,[{adapterId:bridgeId,adapterName:'Amane CCTP V2 Source',adapterVersion:3}],[{recipientId:addressToBytes32(arcAccount),label:'Approved Arc endpoint'}])],leaseIssuers:[]};
await call('install-policy',account,'ArcAuthority','installPolicy',[policy,[await owner.signTypedData(authorityTypedData(11155111,account,'RootPolicy',policy))]]);
const lease={accountId,policyVersion:1n,leaseId:keccak256('0x02'),agent:agent.address,issuer:owner.address,validAfter:now,expiresAt:deadline,activateBefore:deadline,allowedActions:policy.allowedActions,authMode:1,endpoints:policy.endpoints.map(e=>({chainRef:e.chainRef,account:e.account,adapters:e.adapters.map(a=>a.adapterId),assets:e.assets.map(a=>({...a,maxPerAction:20000n,maxPerEpoch:50000n,maxTotal:80000n})),recipients:e.recipients.map(r=>r.recipientId),beneficiaries:[]}))};
await call('activate-lease',account,'ArcAuthority','activateLease',[lease,await owner.signTypedData(authorityTypedData(11155111,account,'AgentLease',lease))]);
const budgetAsset=keccak256('0x03'),policyHash=amaneStructHash('RootPolicy',policy);
await deploy('EndpointQuota','EndpointQuota',[transmitter,'0x00000000000000000000000000000000000a4c03',26,account,evmChainRef(11155111),policyHash,budgetAsset]);
// Arc-only deployment steps (standard-gas local measurement)
await deploy('TransferPayAdapter','TransferPayAdapter');
await deploy('CctpRouteFactory','CctpRouteFactory');
await deploy('GlobalQuotaRoot','GlobalQuotaRoot',[transmitter,policyHash,budgetAsset,100000n,80000n,86400n,7200n,[owner.address],1]);
console.log(JSON.stringify({chainId,rows},null,1));
