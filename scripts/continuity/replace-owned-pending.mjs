import {artifacts} from '@amane/arc';
// Reprice ONLY the one transaction this run signed/submitted; never another wallet user's transaction.
import {readFile,open,rename} from 'node:fs/promises';
import {createPublicClient,http,parseTransaction,recoverTransactionAddress,keccak256,encodeDeployData} from 'viem';import{privateKeyToAccount}from'viem/accounts';
process.on('uncaughtException',e=>{console.error('OWN_REPLACEMENT_STOPPED',String(e.shortMessage??e.message??e.name).slice(0,300));process.exit(1);});
const path='reports/authority-broadcast.json',state=JSON.parse(await readFile(path,'utf8')),entry=state.steps['sepolia-deploy-AdapterRegistry'];
if(!process.argv.includes('--replace-our-recorded-pending')||!entry?.attempted||!entry.raw||entry.receipt||entry.feeBumped)throw Error('NOT_AN_ELIGIBLE_OWN_PENDING_STEP');
const client=createPublicClient({transport:http('https://ethereum-sepolia-rpc.publicnode.com',{timeout:15000,retryCount:0})});if(await client.getChainId()!==11155111)throw Error('WRONG_CHAIN');
let material=(await readFile('/Users/kaushikh/.synq/testnet.key','utf8')).trim();if(!material.startsWith('0x'))material='0x'+material;const owner=privateKeyToAccount(material);if(owner.address!==state.owner)throw Error('WRONG_OWNER');
if(keccak256(entry.raw)!==entry.hash||(await recoverTransactionAddress({serializedTransaction:entry.raw})).toLowerCase()!==owner.address.toLowerCase())throw Error('NOT_OUR_SIGNED_TRANSACTION');
try{await client.getTransactionReceipt({hash:entry.hash});console.log('ALREADY_MINED_NO_REPLACEMENT');process.exit(0);}catch(e){if(e.name!=='TransactionReceiptNotFoundError')throw e;}
const parsed=parseTransaction(entry.raw);let observed;try{observed=await client.getTransaction({hash:entry.hash});}catch(e){if(e.name!=='TransactionNotFoundError')throw e;const latest=await client.getTransactionCount({address:owner.address,blockTag:'latest'}),pending=await client.getTransactionCount({address:owner.address,blockTag:'pending'});if(latest!==entry.nonce||pending!==entry.nonce)throw Error('MISSING_OWN_TX_NONCE_NOT_FREE');entry.droppedAtFreePendingNonce=true;}
if(parsed.to!==undefined||parsed.chainId!==11155111||parsed.nonce!==entry.nonce||(parsed.value??0n)!==0n||parsed.gas!==BigInt(entry.gas)||parsed.data!==encodeDeployData({abi:artifacts.AdapterRegistry.abi,bytecode:artifacts.AdapterRegistry.bytecode,args:[]}))throw Error('ORIGINAL_APPROVED_DEPLOYMENT_MISMATCH');
if(observed&&(observed.blockHash||observed.from.toLowerCase()!==owner.address.toLowerCase()||observed.hash!==entry.hash||observed.nonce!==entry.nonce||observed.input!==parsed.data||observed.to!==null||observed.gas!==parsed.gas))throw Error('OWN_PENDING_IDENTITY_MISMATCH');
if(await client.getTransactionCount({address:owner.address,blockTag:'latest'})!==entry.nonce||await client.getTransactionCount({address:owner.address,blockTag:'pending'})!==(entry.droppedAtFreePendingNonce?entry.nonce:entry.nonce+1))throw Error('SHARED_NONCE_CHANGED');
const pending=await client.getBlock({blockTag:'pending',includeTransactions:true});if(pending.transactions.some(t=>typeof t!=='string'&&t.from.toLowerCase()===owner.address.toLowerCase()&&t.nonce===entry.nonce&&t.hash!==entry.hash))throw Error('OTHER_PENDING_TRANSACTION_DETECTED');
const gas=parsed.gas,maxFeePerGas=500000000n,maxPriorityFeePerGas=1000000n;
if(!gas||BigInt(state.gas.sepolia.units)+gas>40000000n||BigInt(state.gas.sepolia.cost)+gas*maxFeePerGas>20000000000000000n)throw Error('APPROVED_ETH_BUDGET');
const raw=await owner.signTransaction({type:'eip1559',chainId:11155111,nonce:entry.nonce,data:parsed.data,value:0n,gas,maxFeePerGas,maxPriorityFeePerGas});
entry.attempts.push({hash:entry.hash,raw:entry.raw,nonce:entry.nonce,outcome:'OWN_PENDING_FEE_REPLACEMENT_SAME_INTENT'});entry.raw=raw;entry.hash=keccak256(raw);entry.feeBumped=true;entry.attempted=true;
const file=await open(path+'.tmp','w',0o600);try{await file.writeFile(JSON.stringify(state,(_k,v)=>typeof v==='bigint'?v.toString():v,2)+'\n');await file.sync();}finally{await file.close();}await rename(path+'.tmp',path);const dir=await open('reports','r');try{await dir.sync();}finally{await dir.close();}
if(await client.sendRawTransaction({serializedTransaction:raw})!==entry.hash)throw Error('HASH_MISMATCH');console.log('OWN_PENDING_REPRICED',entry.hash);
