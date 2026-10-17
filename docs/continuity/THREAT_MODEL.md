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

## Full authority v3 additions

New v3 code ports original full multi-endpoint policy/issuer checks into a new chain-and-account EIP712 domain; v1/v2 deployed sources and domains are preserved. Root/lease/issuer caps are independent and aggregate across issuer leases. Fixed epoch budgets do not refill mid-period. Every ordinary or reserved destination spend debits the destination budget; an authenticated bridge does not grant an exemption. Only the source authority may invoke the immutable CCTP adapter; signed planHash must match its pinned destination specification.

The CCTP vault validates raw packed source/destination/messageSender/caller/token/hook/fees, invokes the pinned transmitter's actual attestation verifier and measures the exact mint in the same transaction. Fake JSON, donations, replay and fee shortfall do not create intent credit. Source/destination code and immutable route parameters require independent identity checks. Circle attesters and upgrade governance remain trusted; runtime hashes alone do not pin proxy implementation state. Do not claim live interoperability from local fixtures.

Quota grants bind policy, canonical budget asset, endpoint chain/account, epoch, unique nonce, expiry and units. Root outstanding remains encumbered during delay, expiry and freeze pending; only finalized authenticated ACK can return unused quota. Frozen-before-grant tombstones prevent reordering resurrection. Reclaim cannot erase finalized spend. After first asset bind, policy rotation cannot disable quota; before first bind, no global-cap claim is valid. Malicious threshold-authorized root/leaf/code selection is outside the agent-compromise boundary. Provider finality and clock behavior must be explicit route assumptions.

Reimbursement has its own threshold-approved per-lease policy and agent companion signature binding exact action and amount. Fee recipient, gas units, price and every aggregate cap are bounded. Principal and fees share authority and quota; one action nonce prevents replay of either. Measured gas rounds down to ERC20 six-decimal units, so sponsorship can be under-reimbursed but cannot expand the owner's authorized principal budget.

Critical independent review findings were fixed: reserved destination budget bypass; revoke/rotation reservation stranding; source adapter donation DoS; source/destination minimum mismatch; factory deployment-size violation; SDK registry observation mismatch. Tests retain negative cases and original suites. New account runtime is close to EIP170; every financial code change must recheck emitted runtime and factory initcode sizes instead of disabling limits.
