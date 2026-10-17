import {writeFile} from 'node:fs/promises';
import {policyHash,leaseHash,actionHash,typeHashes} from '@amane/policy';
const address=n=>`0x${n.toString(16).padStart(40,'0')}`,bytes32=n=>`0x${n.toString(16).padStart(64,'0')}`;
const p={version:1n,token:address(1),recipient:address(2),adapterId:bytes32(3),recovery:address(4),perAction:20n,perPeriod:40n,total:100n,periodSeconds:100n,maxLeaseLifetime:1000n};
const account=address(100),rootHash=policyHash(p,31337,account);
const l={leaseId:bytes32(5),rootHash,agent:address(6),validAfter:1000n,expiresAt:2000n,perAction:10n,perPeriod:30n,total:80n};
const a={leaseId:l.leaseId,nonce:1n,kind:9,token:p.token,recipient:p.recipient,adapterId:p.adapterId,amount:10n,deadline:1900n,maxFee:0n,feeRecipient:address(0),planHash:bytes32(7)};
await writeFile('vectors/arc-v2.json',JSON.stringify({account,chainId:31337,rootHash,leaseHash:leaseHash(l,31337,account),actionHash:actionHash(a,31337,account),typeHashes},null,2)+'\n');
