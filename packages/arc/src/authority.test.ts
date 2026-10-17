import {it,expect,vi} from 'vitest';
import {AuthorityClient} from './authority.js';
import {keccak256} from 'viem';
const account='0x0000000000000000000000000000000000000011' as const,extension='0x0000000000000000000000000000000000000022' as const,code='0x6000' as const;
const deployment={chainId:31337,account,extension,accountCodeHash:keccak256(code),extensionCodeHash:keccak256(code)};
it('checks full authority account and extension runtime before use',async()=>{const rpc={getChainId:async()=>31337,getCode:async()=>code,readContract:async()=>extension};await expect(new AuthorityClient(rpc as never,deployment).checkIdentity()).resolves.toBeUndefined();});
it('rejects wrong chain and changed extension code',async()=>{const rpc={getChainId:vi.fn(async()=>5042002),getCode:vi.fn(async()=>code),readContract:vi.fn(async()=>extension)};const client=new AuthorityClient(rpc as never,deployment);await expect(client.checkIdentity()).rejects.toThrow('CHAIN_MISMATCH');rpc.getChainId.mockResolvedValue(31337);rpc.getCode.mockResolvedValueOnce(code).mockResolvedValueOnce('0x6001' as never);await expect(client.checkIdentity()).rejects.toThrow('CODE_MISMATCH');});
it('plain JSON cannot bypass resolved-policy signing',async()=>{const client=new AuthorityClient({} as never,deployment);await expect(client.signPolicy({policy:{},chainId:31337,account} as never,{} as never)).rejects.toThrow('UNRESOLVED');});
