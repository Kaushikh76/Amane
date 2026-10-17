import {readFileSync,writeFileSync} from 'node:fs';
import {encodeAbiParameters,hashTypedData,keccak256,toHex} from 'viem';
import {fixturePolicy,fixtureLease,AMANE_TYPES,amaneStructHash} from '../../packages/core/dist/index.js';
import {authorityDomain} from '../../packages/policy/dist/authority.js';
const artifact=JSON.parse(readFileSync('evm/out/ArcAuthority.sol/ArcAuthority.json'));
const policyAbi=artifact.abi.find(x=>x.name==='installPolicy').inputs[0];
const leaseAbi=artifact.abi.find(x=>x.name==='activateLease').inputs[0];
const out=[];
for(let i=0;i<30;i++){
 const policy=fixturePolicy();policy.policyVersion=BigInt(i+1);policy.accountId=keccak256(toHex(`authority-vector-${i}`));policy.endpoints[0].recipients[0].label=`Owner merchant ${i} ✓`;policy.endpoints[0].assets[0].maxTotal+=BigInt(i);
 const lease=fixtureLease();lease.accountId=policy.accountId;lease.policyVersion=policy.policyVersion;lease.leaseId=keccak256(toHex(`authority-lease-${i}`));
 const chainId=[31337,5042002,11155111][i%3],account=`0x${(i+1).toString(16).padStart(40,'0')}`;
 const primaryType=i%2===0?'RootPolicy':'AgentLease',message=i%2===0?policy:lease,abi=i%2===0?policyAbi:leaseAbi;
 out.push({kind:primaryType==='RootPolicy'?0:1,chainId,account,encoded:encodeAbiParameters([abi],[message]),structHash:amaneStructHash(primaryType,message),digest:hashTypedData({domain:authorityDomain(chainId,account),types:AMANE_TYPES,primaryType,message})});
}
writeFileSync('vectors/authority-v3.json',JSON.stringify({vectors:out},null,2)+'\n');
console.log(`Generated ${out.length} authority v3 differential vectors`);
