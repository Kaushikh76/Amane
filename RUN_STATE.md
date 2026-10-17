# Continuity run state

Restricted Arc PAY release candidate prepared and tested. Full A00–A17 protocol is PARTIAL, not production-ready. See deployments/arc-testnet.json, docs/continuity/COMPATIBILITY.md and the owner coordination release handoff for exact scope/pins.

Baseline: b57f2484a43c58ee7a64cfd48c3792c8638dfcf7. Branch: build/amane-continuity-v2-arc. Original v1 source and domains unchanged. Sui upgraded to 1.81.1; 127 TS, 212 Foundry and 126 Move tests pass. Independent critic reviewed the supported PAY scope and live runner.

Live: 25 owner-approved Arc testnet transactions. 0.05 USDC funded, 0.02 paid, 0.03 recovered, 0.2108051 USDC gas. No Sepolia or mainnet broadcast. Demonstration lease revoked and residual treasury recovered. Root/relayer same funded EOA by explicit owner override; separate unfunded agent. Do not reuse the shared Synq operator's nonce or replace unrelated transactions.

Blocked/unimplemented: authenticated CCTP source/arrival verification, global quota coupling/authenticated sync, SWAP/ESCROW targets, delegated issuer/reimbursement clauses, v2 Move parity, Circle/Safe/1271/7579 integration. The local quota prototype is not a global account cap. Unsupported capabilities stay disabled.

No npm publication, signed release tag, remote push or explorer source submission. Local tarballs and ignored reports are for owner review. Further financial integration must use the exact claimed subset and owner-approved setup; no blanket permission follows from a partial handoff.
