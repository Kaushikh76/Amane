// Executes only the owner-approved Arc testnet plan; private material stays in this signer process.
import {readFile,writeFile,rename,open,mkdir} from 'node:fs/promises';
import {createPublicClient,http,encodeDeployData,encodeFunctionData,keccak256,decodeEventLog,parseAbi} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import {artifacts,arcTestnet,verifyArc} from '@amane/arc';
import {compilePolicy,domain,types,actionHash} from '@amane/policy';
import {verifyExecution} from '@amane/verify';
process.on('uncaughtException',error=>{console.error('BROADCAST_STOPPED',error.shortMessage??error.message??error.name);process.exit(1);});
const EXECUTE=process.argv.includes('--execute-approved-plan');
const client=createPublicClient({chain:arcTestnet,transport:http('https://rpc.testnet.arc.io',{timeout:20000,retryCount:1}),pollingInterval:1000});
const chain=await verifyArc(client);
const approvedUsdcHash='0xc9987bd3af6b26a030951faa7eacc017b68343aeedf3ce5fe68f821c4b93939d';
async function verifyToken(){const code=await client.getCode({address:'0x3600000000000000000000000000000000000000'});if(!code || keccak256(code)!==approvedUsdcHash)throw new Error('USDC_CODEHASH_MISMATCH');}
await verifyToken();
if(!EXECUTE){console.log('Read-only preflight passed; no key read or broadcast. Use --execute-approved-plan only with recorded owner approval.');process.exit(0);}
const recordPath='reports/approved-broadcast.json',zero='0x0000000000000000000000000000000000000000';
const recipient='0x263174780015983489C0987e4AB1886e7Ab8348E',recovery='0x6BD6Db75B56acE65019AA08FCAd4778808Da08bD';
const loadKey=async path=>{let x=(await readFile(path,'utf8')).trim();if(!x.startsWith('0x'))x='0x'+x;if(!/^0x[0-9a-fA-F]{64}$/.test(x))throw new Error('KEY_FILE_ENCODING');return privateKeyToAccount(x);};
const owner=await loadKey('/Users/kaushikh/.synq/testnet.key'),agent=await loadKey('/Users/kaushikh/.synq/amane-agent.key');
if(owner.address.toLowerCase()!==recovery.toLowerCase() || agent.address===owner.address)throw new Error('KEY_IDENTITY_MISMATCH');
let state;try{state=JSON.parse(await readFile(recordPath,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;state={chainId:5042002,owner:owner.address,agent:agent.address,startedAt:new Date().toISOString(),timestamp:String((await client.getBlock()).timestamp),steps:{},contracts:{},principalFunding:'0',gasUsed:'0',gasCostWei:'0'};}
if(state.owner!==owner.address || state.agent!==agent.address || state.chainId!==5042002)throw new Error('RUN_IDENTITY_CONFLICT');
const save=async()=>{await mkdir('reports',{recursive:true});const f=await open(recordPath+'.tmp','w',0o600);try{await f.writeFile(JSON.stringify(state,(_key,value)=>typeof value==='bigint'?value.toString():value,2)+'\n');await f.sync();}finally{await f.close();}await rename(recordPath+'.tmp',recordPath);const directory=await open('reports','r');try{await directory.sync();}finally{await directory.close();}};
const MAX_GAS=35000000n,MAX_FEE=50000000000n,MAX_GAS_COST=1750000000000000000n,MAX_PRINCIPAL=50000n;
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function receiptIfKnown(hash){try{return await client.getTransactionReceipt({hash});}catch(e){if(e.name==='TransactionReceiptNotFoundError')return undefined;throw e;}}
async function confirmed(hash){const receipt=await client.waitForTransactionReceipt({hash,confirmations:3,timeout:180000});const block=await client.getBlock({blockNumber:receipt.blockNumber});if(block.hash!==receipt.blockHash)throw new Error('REORG_PENDING');return receipt;}
async function consumedByOther(nonce,ourHash){const latest=await client.getBlockNumber();if(await client.getTransactionCount({address:owner.address,blockNumber:latest})<=nonce)return false;for(let i=0n;i<64n && latest>=i;i++){const block=await client.getBlock({blockNumber:latest-i,includeTransactions:true});for(const tx of block.transactions){if(typeof tx!=='string' && tx.from.toLowerCase()===owner.address.toLowerCase() && tx.nonce===nonce){if(tx.hash===ourHash)return false;const receipt=await confirmed(tx.hash);state.nonceConflictEvidence={ourHash,nonce,otherHash:tx.hash,blockHash:receipt.blockHash};await save();return true;}}}return false;}
async function step(name,{to,data,value=0n,gasCeiling=1000000n,expectedRevert=false,funding=0n}) {
 await verifyToken();
 if(await client.getChainId()!==5042002)throw new Error('WRONG_CHAIN');
 let entry=state.steps[name];const requestHash=keccak256(new TextEncoder().encode(JSON.stringify({to,data,value:String(value),expectedRevert})));
 if(entry && entry.requestHash!==requestHash)throw new Error('STEP_MUTATION_'+name);
 if(entry?.receipt){const receipt=await confirmed(entry.receipt.transactionHash);if(receipt.blockHash!==entry.receipt.blockHash)throw new Error('RECORDED_STEP_REORGED');return entry.receipt;}
 if(BigInt(state.principalFunding)+funding>MAX_PRINCIPAL)throw new Error('PRINCIPAL_CEILING');
 if(!entry){entry={requestHash,attempts:[]};state.steps[name]=entry;}
 for(let retry=0;retry<4;++retry){
  if(!entry.raw){
   const quotedFee=await client.getGasPrice();if(quotedFee>MAX_FEE)throw new Error('FEE_CEILING');
   let gas=gasCeiling;
   if(!expectedRevert){const estimate=await client.estimateGas({account:owner.address,to,data,value});gas=estimate*12n/10n+10000n;if(gas>gasCeiling)throw new Error('CALL_GAS_CEILING_'+name);}
   if(BigInt(state.gasUsed)+gas>MAX_GAS || BigInt(state.gasCostWei)+gas*MAX_FEE>MAX_GAS_COST)throw new Error('AGGREGATE_GAS_CEILING');
   // Shared Synq operator: read pending nonce immediately, never use a private nonce counter.
   const nonce=await client.getTransactionCount({address:owner.address,blockTag:'pending'});
   const tx={type:'eip1559',chainId:5042002,nonce,to,data,value,gas,maxFeePerGas:quotedFee,maxPriorityFeePerGas:0n};
   entry.raw=await owner.signTransaction(tx);entry.hash=keccak256(entry.raw);entry.nonce=nonce;entry.gas=String(gas);entry.submissionAttempted=false;await save();
  }
  let receipt=await receiptIfKnown(entry.hash);
  if(!receipt){
   if(!entry.submissionAttempted){
    let pendingTransactions=[];try{pendingTransactions=(await client.getBlock({blockTag:'pending',includeTransactions:true})).transactions;}catch(error){if(error.cause?.code!==-32014 && error.code!==-32014)throw error;state.pendingBlockInspection='RPC_UNAVAILABLE_-32014; pending nonce checked before each send; no fee bump';}
    const conflict=pendingTransactions.find(tx=>typeof tx!=='string' && tx.from.toLowerCase()===owner.address.toLowerCase() && tx.nonce===entry.nonce && tx.hash!==entry.hash);
    const freshPending=await client.getTransactionCount({address:owner.address,blockTag:'pending'});
    if(conflict || freshPending!==entry.nonce){entry.attempts.push({hash:entry.hash,nonce:entry.nonce,outcome:'NOT_SUBMITTED_PENDING_NONCE_CHANGED'});delete entry.raw;delete entry.hash;await save();continue;}
   }
   entry.submissionAttempted=true;await save();
   try{const hash=await client.sendRawTransaction({serializedTransaction:entry.raw});if(hash!==entry.hash)throw new Error('HASH_MISMATCH');}
   catch(e){
    receipt=await receiptIfKnown(entry.hash);
    if(!receipt){
     const message=String(e.shortMessage??e.name??'RPC_ERROR');
     if(/nonce|replacement.*underpriced|already.*used/i.test(message)){
      // Reconcile our hash first. A retry always gets a new pending nonce and never fee-replaces another tx.
      for(let n=0;n<3 && !receipt;n++){await wait(1000);receipt=await receiptIfKnown(entry.hash);}
      if(!receipt){
       if(!await consumedByOther(entry.nonce,entry.hash))throw new Error('NONCE_CONFLICT_REQUIRES_RECONCILIATION');
       entry.attempts.push({hash:entry.hash,nonce:entry.nonce,outcome:'NONCE_CONSUMED_BY_OTHER_CONFIRMED_TX'});delete entry.raw;delete entry.hash;await save();continue;
      }
     }else if(!/known|already/i.test(message))throw new Error('SUBMISSION_FAILED_'+name+'_'+message);
    }
   }
   if(!receipt)receipt=await client.waitForTransactionReceipt({hash:entry.hash,confirmations:3,timeout:180000});
  }
  receipt=await confirmed(entry.hash);
  if(receipt.status!==(expectedRevert?'reverted':'success'))throw new Error('UNEXPECTED_RECEIPT_'+name);
  const canonical=await client.getBlock({blockNumber:receipt.blockNumber});if(canonical.hash!==receipt.blockHash)throw new Error('REORG_PENDING');
  entry.receipt={transactionHash:receipt.transactionHash,status:receipt.status,contractAddress:receipt.contractAddress,blockNumber:String(receipt.blockNumber),blockHash:receipt.blockHash,gasUsed:String(receipt.gasUsed),effectiveGasPrice:String(receipt.effectiveGasPrice)};
  state.gasUsed=String(BigInt(state.gasUsed)+receipt.gasUsed);state.gasCostWei=String(BigInt(state.gasCostWei)+receipt.gasUsed*receipt.effectiveGasPrice);state.principalFunding=String(BigInt(state.principalFunding)+funding);await save();
  console.log(name,receipt.status,receipt.transactionHash);return entry.receipt;
 }
 throw new Error('NONCE_RETRIES_EXHAUSTED');
}
function stripImmutables(code,refs){let s=code.slice(2);for(const list of Object.values(refs))for(const {start,length} of list)s=s.slice(0,start*2)+'0'.repeat(length*2)+s.slice((start+length)*2);return s;}
async function verifyRuntime(name,address){const artifact=artifacts[name],code=await client.getCode({address});if(!code || stripImmutables(code,artifact.immutableReferences)!==stripImmutables(artifact.deployedBytecodeTemplate,artifact.immutableReferences))throw new Error('RUNTIME_TEMPLATE_MISMATCH_'+name);state.contracts[name]={address,codeHash:keccak256(code)};await save();return address;}
async function deploy(name,args=[],gasCeiling=4500000n){await verifyToken();if(state.contracts[name])return verifyRuntime(name,state.contracts[name].address);const artifact=artifacts[name];const receipt=await step('deploy-'+name,{data:encodeDeployData({abi:artifact.abi,bytecode:artifact.bytecode,args}),gasCeiling});if(!receipt.contractAddress)throw new Error('MISSING_CONTRACT');return verifyRuntime(name,receipt.contractAddress);}
const call=async(name,address,artifact,functionName,args=[],options={})=>step(name,{to:address,data:encodeFunctionData({abi:artifacts[artifact].abi,functionName,args}),...options});
const read=(address,artifact,functionName,args=[])=>client.readContract({address,abi:artifacts[artifact].abi,functionName,args});
const registry=await deploy('AdapterRegistry',[],1500000n),adapter=await deploy('TransferPayAdapter',[],1500000n);
if(!state.adapterId){await call('register-pay',registry,'AdapterRegistry','register',[adapter]);const hash=state.steps['register-pay'].receipt.transactionHash;const receipt=await client.getTransactionReceipt({hash});const event=receipt.logs.flatMap(log=>{try{return [decodeEventLog({abi:artifacts.AdapterRegistry.abi,...log})];}catch{return [];}}).find(x=>x.eventName==='AdapterRegistered');if(!event)throw new Error('REGISTER_EVENT');state.adapterId=event.args.adapterId;await save();}
const factory=await deploy('ArcFactory',[registry]),salt=keccak256(new TextEncoder().encode('Amane Continuity '+state.timestamp));
const account=await read(factory,'ArcFactory','predict',[[owner.address],1,salt]);await call('create-account',factory,'ArcFactory','create',[[owner.address],1,salt],{gasCeiling:4500000n});await verifyRuntime('ArcAccount',account);
await call('create-idempotent',factory,'ArcFactory','create',[[owner.address],1,salt],{gasCeiling:500000n});
if(await read(account,'ArcAccount','deploymentChainId')!==5042002n || (await read(account,'ArcAccount','registry')).toLowerCase()!==registry.toLowerCase() || await read(account,'ArcAccount','threshold')!==1 || !await read(account,'ArcAccount','controller',[owner.address]))throw new Error('IMMUTABLE_IDENTITY');
const vaultFactory=await deploy('IntentVaultFactory',[],1500000n);
const token='0x3600000000000000000000000000000000000000',now=BigInt(state.timestamp),deadline=now+7200n;
const root={version:1n,token,recipient,adapterId:state.adapterId,recovery,perAction:10000n,perPeriod:20000n,total:30000n,periodSeconds:86400n,maxLeaseLifetime:86400n};
const compiled=compilePolicy(root,5042002,account),sign=(primaryType,message)=>owner.signTypedData({domain:domain(5042002,account),types,primaryType,message});
if(!state.steps['install-policy']?.receipt){const nonce=await read(account,'ArcAccount','controlNonce'),signature=await sign('Control',{operation:compiled.rootHash,target:account,nonce,deadline});await call('install-policy',account,'ArcAccount','installPolicy',[root,deadline,[signature]]);}
const lease={leaseId:keccak256(new TextEncoder().encode('Amane lease '+state.timestamp)),rootHash:compiled.rootHash,agent:agent.address,validAfter:now,expiresAt:deadline,perAction:10000n,perPeriod:20000n,total:30000n};
await call('activate-lease',account,'ArcAccount','activateLease',[lease,[await sign('AgentLease',lease)]]);
const tokenAbi=parseAbi(['function transfer(address,uint256) returns (bool)','function balanceOf(address) view returns (uint256)']);
await step('fund-account',{to:token,data:encodeFunctionData({abi:tokenAbi,functionName:'transfer',args:[account,30000n]}),funding:30000n});
const makeAction=(nonce,amount=10000n)=>({leaseId:lease.leaseId,nonce,kind:9,token,recipient,adapterId:state.adapterId,amount,deadline,maxFee:0n,feeRecipient:zero,planHash:keccak256(new TextEncoder().encode('Amane proof '+state.timestamp+' '+nonce))});
const agentSig=action=>agent.signTypedData({domain:domain(5042002,account),types,primaryType:'ActionIntent',message:action});
const pay=makeAction(1n);const paySig=await agentSig(pay);
if(!state.before){state.before={recipient:String(await client.readContract({address:token,abi:tokenAbi,functionName:'balanceOf',args:[recipient]}))};await save();}
await call('allowed-pay',account,'ArcAccount','execute',[pay,paySig]);
const malicious={...makeAction(2n,1000n),recipient:agent.address};await call('denied-redirect',account,'ArcAccount','execute',[malicious,await agentSig(malicious)],{expectedRevert:true,gasCeiling:500000n});
await call('denied-replay',account,'ArcAccount','execute',[pay,paySig],{expectedRevert:true,gasCeiling:500000n});
await call('pause',account,'ArcAccount','pause',[],{gasCeiling:750000n});const paused=makeAction(3n,1000n);await call('denied-paused',account,'ArcAccount','execute',[paused,await agentSig(paused)],{expectedRevert:true,gasCeiling:500000n});
if(!state.steps.unpause?.receipt){const epoch=await read(account,'ArcAccount','pauseEpoch'),nonce=await read(account,'ArcAccount','controlNonce');const {encodeAbiParameters}=await import('viem');const operation=keccak256(encodeAbiParameters([{type:'string'},{type:'uint256'}],['UNPAUSE',epoch]));await call('unpause',account,'ArcAccount','unpause',[deadline,[await sign('Control',{operation,target:account,nonce,deadline})]],{gasCeiling:750000n});}
async function vault(label,action){const address=await read(vaultFactory,'IntentVaultFactory','predict',[account,action]);await call('create-vault-'+label,vaultFactory,'IntentVaultFactory','create',[account,action],{gasCeiling:1500000n});const code=await client.getCode({address});if(!code || stripImmutables(code,artifacts.IntentVault.immutableReferences)!==stripImmutables(artifacts.IntentVault.deployedBytecodeTemplate,artifacts.IntentVault.immutableReferences))throw new Error('VAULT_CODE');state.contracts['IntentVault-'+label]={address,codeHash:keccak256(code)};await save();await step('fund-vault-'+label,{to:token,data:encodeFunctionData({abi:tokenAbi,functionName:'transfer',args:[address,10000n]}),funding:10000n});return address;}
const reserved=makeAction(2n),reservedVault=await vault('reserved',reserved);await call('reserved-pay',account,'ArcAccount','executeVault',[reserved,await agentSig(reserved),reservedVault]);
const late=makeAction(4n),lateVault=await vault('late',late);await call('revoke',account,'ArcAccount','revoke',[lease.leaseId],{gasCeiling:750000n});await call('denied-revoked',account,'ArcAccount','executeVault',[late,await agentSig(late),lateVault],{expectedRevert:true,gasCeiling:500000n});
if(!state.steps['recover-late']?.receipt){const nonce=await read(account,'ArcAccount','controlNonce');await call('recover-late',account,'ArcAccount','recoverVault',[lateVault,deadline,[await sign('Control',{operation:keccak256(new TextEncoder().encode('RECOVER_VAULT')),target:lateVault,nonce,deadline})]],{gasCeiling:750000n});}
if(!state.steps['withdraw-remainder']?.receipt){const nonce=await read(account,'ArcAccount','controlNonce'),amount=20000n;const {encodeAbiParameters}=await import('viem');const operation=keccak256(encodeAbiParameters([{type:'string'},{type:'bytes32'},{type:'uint256'}],['WITHDRAW',compiled.rootHash,amount]));await call('withdraw-remainder',account,'ArcAccount','withdraw',[amount,deadline,[await sign('Control',{operation,target:recovery,nonce,deadline})]],{gasCeiling:750000n});}
const verified=await verifyExecution(client,account,state.contracts.ArcAccount.codeHash,pay,state.steps['allowed-pay'].receipt.transactionHash);
const after=await client.readContract({address:token,abi:tokenAbi,functionName:'balanceOf',args:[recipient]});if(after-BigInt(state.before.recipient)!==20000n)throw new Error('RECIPIENT_DELTA_MISMATCH');
state.result={proofLevel:'LIVE_ARC_TESTNET',rootHash:compiled.rootHash,leaseId:lease.leaseId,permittedIntentHash:actionHash(pay,5042002,account),recipientDelta:'20000',verified,sourceProvenance:'UNAVAILABLE',rootAndRelayerSameOwnerOverride:true,completeAt:new Date().toISOString()};await save();console.log('Approved Arc suite complete; principal plus gas within ceilings.');
