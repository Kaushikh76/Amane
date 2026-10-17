# Continuity v2 threat model

Unaudited. This document distinguishes the existing Sui/Sepolia protocol from new Arc modules.

Human threshold -> root policy -> bounded issuer -> agent lease -> exact signed intent -> permissionless relay -> custody contract -> measured token effect -> independent receipt verification.

| Principal / boundary | Privilege | Failure and enforcing check |
|---|---|---|
| Root threshold | Install policy, recover to pinned address | Full threshold compromise is out of scope; nonce-bound changes, expiry and pinned recovery constrain accidents |
| Issuer | Issue a subset lease | Issuer/agent identity separate; aggregate root budget is still enforced |
| Agent / model | Propose and sign only leased intent | Recipient, action, token, chain, endpoint, version, amount, fee and nonce all contract checked |
| Relayer | Pay gas, submit unchanged signatures | Cannot mutate data; duplicate nonce reverts atomically; may censor, another relay can submit |
| Adapter | Consume exact input | Registry pins code, account measures delivery; mutable upstream must be separately pinned or capability unavailable |
| RPC / indexer | Observe data | Never authority; mismatched receipts remain unknown; local tests are not live proof |
| CCTP | Authenticate transport mint | Does not authenticate arbitrary application JSON; isolated custody alone is OFFCHAIN_PROVENANCE |
| Quota leaf | Spend discrete allocation | Cross-chain reclaim cannot unlock without authenticated final closure; timeout alone never returns authority |
| Safe/Circle/1271 | Potential controller | EOA restrictions only on contract custody; unknown module/signature compatibility BLOCKED |
| Sui | Existing native endpoint | Preserve v1 domain/Move semantics; no fabricated translation parity for new v2 |

## Reproducible existing defenses and limits

Run `cd evm && forge test`. Existing tests cover recipient substitution (`test_HOLDS_pay_recipient_substitution_rejected`), nonce replay (`test_HOLDS_nonce_replay_rejected`), multiple leases sharing root budget (`test_HOLDS_multiple_leases_share_root_budget`), revoked lease (`test_HOLDS_revoke_blocks_action_and_activation`), pause (`test_HOLDS_pause_blocks_action`), mutable adapter (`test_FIXED_F0204_proxy_adapter_refused`), token quirks (`test_HOLDS_token_quirks`), signed cross-chain tamper (`test_HOLDS_action_cross_chain_and_tamper_rejected`), expired reservations and premature recovery (`test_WH_011_recovery_path_refused_while_the_destination_is_still_deliverable`). Baseline output is under reports/baseline.

Limits: v1 token buckets permit a documented burst plus linear refill, not a strict rolling-period cap. Cross-chain exposure is the sum of endpoint caps. Existing Wormhole reservations do not establish CCTP support. A signature valid on v1 is not a v2 authorization. Native Arc USDC and ERC20 USDC are representations of one economic balance. Source-map-js advisory currently follows the development-only Vitest/Vite/PostCSS path; retain evidence and avoid an unrelated baseline upgrade.

## New implementation ceilings

Arc v2 initially admits exact ERC20 PAY through the existing immutable TransferPayAdapter, with a separate signing domain and strict fixed-period and cumulative counters. SWAP, BRIDGE and ESCROW_FUND must fail closed until their exact adapter/provenance requirements are implemented and proven. No generic CALL or delegatecall extension is admitted in the new module. Preserve all original v1 entry points and files.

Map authority, conservation, replay, custody, recipient, escalation, receipts, transport, quarantine, revocation, precision, neutrality, identity, finality and mainnet gating to the inherited 18 invariants. Any missing live or cross-language proof downgrades a capability instead of weakening an invariant.
