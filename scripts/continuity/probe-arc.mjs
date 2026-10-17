import {writeFile} from 'node:fs/promises';import {createPublicClient,http,parseAbi,keccak256} from 'viem';
const c=createPublicClient({transport:http('https://rpc.testnet.arc.io',{timeout:15000,retryCount:0})});
const usdc='0x3600000000000000000000000000000000000000';
const [chainId,blockNumber,gasPrice,decimals,code]=await Promise.all([c.getChainId(),c.getBlockNumber(),c.getGasPrice(),c.readContract({address:usdc,abi:parseAbi(['function decimals() view returns (uint8)']),functionName:'decimals'}),c.getCode({address:usdc})]);
if(chainId!==5042002 || decimals!==6 || !code)throw new Error('Arc registry mismatch');
const proof={chainId,blockNumber:blockNumber.toString(),gasPriceWei:gasPrice.toString(),decimals,usdc,codeHash:keccak256(code),observedAt:new Date().toISOString(),proofLevel:'READ_ONLY_SINGLE_RPC'};await writeFile('reports/arc-rpc-probe.json',JSON.stringify(proof,null,2)+'\n');console.log(JSON.stringify(proof));
