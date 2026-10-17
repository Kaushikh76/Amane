# Continuity run state

Restricted Arc PAY release candidate prepared and tested. Full A00–A17 protocol is PARTIAL, not production-ready. See deployments/arc-testnet.json, docs/continuity/COMPATIBILITY.md and the owner coordination release handoff for exact scope/pins.

Baseline: b57f2484a43c58ee7a64cfd48c3792c8638dfcf7. Branch: build/amane-continuity-v2-arc. Original v1 source and domains unchanged. Sui upgraded to 1.81.1; 127 TS, 212 Foundry and 126 Move tests pass. Independent critic reviewed the supported PAY scope and live runner.

Live: 25 owner-approved Arc testnet transactions. 0.05 USDC funded, 0.02 paid, 0.03 recovered, 0.2108051 USDC gas. No Sepolia or mainnet broadcast. Demonstration lease revoked and residual treasury recovered. Root/relayer same funded EOA by explicit owner override; separate unfunded agent. Do not reuse the shared Synq operator's nonce or replace unrelated transactions.

Blocked/unimplemented: authenticated CCTP source/arrival verification, global quota coupling/authenticated sync, SWAP/ESCROW targets, delegated issuer/reimbursement clauses, v2 Move parity, Circle/Safe/1271/7579 integration. The local quota prototype is not a global account cap. Unsupported capabilities stay disabled.

No npm publication, signed release tag, remote push or explorer source submission. Local tarballs and ignored reports are for owner review. Further financial integration must use the exact claimed subset and owner-approved setup; no blanket permission follows from a partial handoff.

## Full authority v3 continuation

The restricted v2 proof remains archived at its original SHA. Work resumed the original full mandate: new ArcAuthority port preserves all original Sui/Sepolia files and domain compatibility; new chain/address-bound v3 domain, multi-recipient/assets, issuer aggregates, exact measurements, strict compiler and registry resolver. Added owner+agent bounded fees, pinned escrow protocol credit, source-only CCTP burn, raw-message authenticated mint vault, destination budgets/quarantine, global quota root and authenticated leaf sync integrated into expenditure. Full tests/release pin follow below; no new broadcasts authorized. See ADR-FULL-AUTHORITY-PORT and shared v3_DRAFT handoff. Independent findings and fixes under ignored reports/critic. Factory EIP170 failure discovered by localhost SDK integration was fixed with two inert pinned creation-code stores; no code-size-limit bypass used.

## Approved quota patch and broadcast resumption

Package candidate0.3.1/source7236a773dcde33d750026c4aac35b60874ac86dd corrects authenticated same-domain quota delivery; remote CCTP remains unchanged.264 Foundry pass;152 TS pass across workspace plus isolated policy rerun (one initial host-load timeout); prior126 Move unchanged. Fresh runtime consumer passes. Owner approved complete amendment and exact corrected quota bytecodes. Sepolia registry deployment confirmed at0x0b35078c1dbc882872fcba82c513b4b4a4fa07af2952af1ea84f4153bb90e6de. No v3 principal funded; subsequent extension gas estimate above approved ceiling is under investigation. Earlier no-Sepolia/no-new-approval statements describe historical snapshots only.

## Release readiness pass (local only)

Local-only work, no broadcast, no key read. Sui Move now carries Arc v2 (restricted PAY) and v3 (full authority) hash/domain parity in the additive module `amane::arc_eip712` with generated golden tests (`sui/amane/tests/arc_parity_tests.move`, from vectors/arc-v2.json and vectors/authority-v3.json); v1 sources and domain unchanged; the earlier "v2 Move parity" blocker is closed at LOCAL_UNIT level (Sui does not enforce Arc authority). Added a stateful quota invariant suite (random allocate/spend/freeze/duplicate and reordered delivery/time; mutation-checked) and seeded subset property tests; no contract defect found. The Sepolia gas stop is explained by chain state-creation repricing (about 1,549 gas per deployed code byte instead of 200); measurement and a minimal amendment request are in the owner coordination blocker `amane-sepolia-gas-amendment.md`; the opt-in runner path now carries the exact requested ceilings. Not run, needs owner approval.
