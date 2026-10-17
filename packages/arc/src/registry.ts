import { defineChain, keccak256, type Address, type Hex, type PublicClient } from 'viem';
export const ARC_USDC = '0x3600000000000000000000000000000000000000' as const;
export const arcTestnet = defineChain({id:5042002,name:'Arc Testnet',nativeCurrency:{name:'USDC',symbol:'USDC',decimals:18},rpcUrls:{default:{http:['https://rpc.testnet.arc.io']}},blockExplorers:{default:{name:'Arc Explorer',url:'https://explorer.testnet.arc.io'}},testnet:true});
export const registry = {chainId:5042002,erc20:{address:ARC_USDC,decimals:6},native:{decimals:18},economicAsset:'USDC',cctp:{version:2,sourceDomain:0,destinationDomain:26,provenance:'UNAVAILABLE'}} as const;
export function nativeToErc20(wei:bigint):{units:bigint;dustWei:bigint} {if(wei<0n)throw new Error('NEGATIVE_AMOUNT');return {units:wei/10n**12n,dustWei:wei%10n**12n};}
export function parseUsdc(value:string):bigint {
 if(!/^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/.test(value)) throw new Error('INVALID_USDC_AMOUNT');
 const [whole,fraction='']=value.split('.');return BigInt(whole!)*1000000n+BigInt(fraction.padEnd(6,'0'));
}
export async function verifyDeployment(client:PublicClient,address:Address,expectedCodeHash:Hex):Promise<Hex> {
 if(await client.getChainId()!==5042002 && await client.getChainId()!==31337) throw new Error('UNSUPPORTED_CHAIN');
 const code=await client.getCode({address});if(!code || code==='0x' || keccak256(code)!==expectedCodeHash) throw new Error('CODEHASH_MISMATCH');return expectedCodeHash;
}
export async function verifyArc(client:PublicClient) {
 if(await client.getChainId()!==5042002)throw new Error('CHAIN_MISMATCH');
 const decimals=await client.readContract({address:ARC_USDC,abi:[{type:'function',name:'decimals',inputs:[],outputs:[{type:'uint8'}],stateMutability:'view'}],functionName:'decimals'});
 if(decimals!==6)throw new Error('DECIMAL_MISMATCH');return registry;
}
