import {it,expect} from 'vitest';
import {concatHex,toHex} from 'viem';
import {authorityHook,inspectAuthorityBurn,encodeAuthorityRedemption} from './authority.js';
const a='0x0000000000000000000000000000000000000001' as const,b='0x0000000000000000000000000000000000000002' as const,intent=toHex(77,{size:32});
function message(fee=3){return concatHex([toHex(1,{size:4}),toHex(0,{size:4}),toHex(26,{size:4}),toHex(1,{size:32}),toHex(2,{size:32}),toHex(3,{size:32}),toHex(4,{size:32}),toHex(2000,{size:4}),toHex(2000,{size:4}),toHex(1,{size:4}),toHex(5,{size:32}),toHex(4,{size:32}),toHex(100,{size:32}),toHex(6,{size:32}),toHex(10,{size:32}),toHex(fee,{size:32}),toHex(0,{size:32}),authorityHook(a,b,intent,toHex(88,{size:32}))]);}
it('inspects exact packed CCTP V2 offsets without claiming authentication',()=>{const m=inspectAuthorityBurn(message());expect(m.sourceDomain).toBe(0);expect(m.destinationDomain).toBe(26);expect(m.amount-m.fee).toBe(97n);expect(m.sourceAccount).toBe(a);expect(m.destinationAccount).toBe(b);expect(m.intent).toBe(intent);expect(m.proofLevel).toBe('UNAUTHENTICATED_BYTES');});
it('rejects malformed length, excessive fee and invalid attestation encoding',()=>{expect(()=>inspectAuthorityBurn('0x1234')).toThrow();expect(()=>inspectAuthorityBurn(message(11))).toThrow('INVALID_FEE');expect(()=>encodeAuthorityRedemption(message(),'0x12')).toThrow('INVALID_ATTESTATION');});
it('encodes bytes for actual onchain verifier without treating them as verified',()=>{expect(encodeAuthorityRedemption(message(),`0x${'11'.repeat(65)}`)).toMatch(/^0x/);});
