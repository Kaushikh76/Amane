import {it,expect} from 'vitest';
import {parseUsdc,nativeToErc20,verifyArc,verifyDeployment} from '../src/registry.js';
import {FileRelayJournal} from '../src/journal.js';
import {mkdtemp,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';
it('integer USDC and native mirror reconcile once including dust',()=>{expect(parseUsdc('1')).toBe(1000000n);expect(parseUsdc('0.000001')).toBe(1n);expect(nativeToErc20(10n**18n+1n)).toEqual({units:1000000n,dustWei:1n});});
for(const x of ['1e6','-1','0.0000001','NaN','01','1,000','1.',' 1'])it(`rejects ${x}`,()=>expect(()=>parseUsdc(x)).toThrow());
it('provider chain and decimal mismatch fail closed',async()=>{await expect(verifyArc({getChainId:async()=>1} as never)).rejects.toThrow();await expect(verifyArc({getChainId:async()=>5042002,readContract:async()=>18} as never)).rejects.toThrow();});
it('missing deployment cannot pass verification',async()=>{await expect(verifyDeployment({getChainId:async()=>31337,getCode:async()=>undefined} as never,'0x0000000000000000000000000000000000000001',`0x${'11'.repeat(32)}`)).rejects.toThrow();});
it('concurrent relayers reserve one obligation; signed bytes survive restart',async()=>{const dir=await mkdtemp(join(tmpdir(),'amane-journal-'));try{const j=new FileRelayJournal(dir),h=`0x${'11'.repeat(32)}` as const;const results=await Promise.all([j.reserve('job',h),j.reserve('job',h)]);expect(results.filter(Boolean)).toHaveLength(1);await j.save('job',{intentHash:h,status:'SIGNED',rawTransaction:'0x1234',transactionHash:h});expect(await new FileRelayJournal(dir).read('job')).toMatchObject({rawTransaction:'0x1234',status:'SIGNED'});}finally{await rm(dir,{recursive:true,force:true});}});
