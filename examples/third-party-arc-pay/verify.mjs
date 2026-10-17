// Read-only independent proof verification. No private keys, Synq packages or broadcasts.
import {readFile} from 'node:fs/promises';
import {createPublicClient,http} from 'viem';
import {arcTestnet,verifyArc} from '@amane/arc';
import {verifyExecution} from '@amane/verify';
const manifest=JSON.parse(await readFile(new URL('../../deployments/arc-testnet.json',import.meta.url),'utf8'));
const client=createPublicClient({chain:arcTestnet,transport:http(arcTestnet.rpcUrls.default.http[0],{timeout:20000,retryCount:1})});
await verifyArc(client);
const {intent,transactionHash}=manifest.proofs.permittedPay;
const action={...intent,nonce:BigInt(intent.nonce),amount:BigInt(intent.amount),deadline:BigInt(intent.deadline),maxFee:BigInt(intent.maxFee)};
const account=manifest.contracts.ArcAccount.address;
const proof=await verifyExecution(client,account,manifest.contracts.ArcAccount.codeHash,action,transactionHash);
const denied=await client.getTransactionReceipt({hash:manifest.proofs.deniedRedirect.transactionHash});
if(denied.status!=='reverted' || denied.to.toLowerCase()!==account.toLowerCase())throw new Error('Denied proof does not match account/revert');
const block=await client.getBlock({blockNumber:denied.blockNumber});if(block.hash!==denied.blockHash)throw new Error('Denied receipt reorged');
console.log(JSON.stringify({status:'VERIFIED_TESTNET_PAY_AND_REJECTED_REDIRECT',account,codeHash:manifest.contracts.ArcAccount.codeHash,permitted:proof.transactionHash,denied:denied.transactionHash,amountBaseUnits:String(proof.amountBaseUnits),cctpProvenance:'UNAVAILABLE',finality:'Canonical block observed; see chain confirmations and reorg caveat'},null,2));
