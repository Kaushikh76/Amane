# Capability and enforcement matrix

This is an unaudited testnet release candidate. Only the new Arc PAY subset is implemented. Existing Sui/Sepolia v1 behavior remains supported as before.

| Path | Enforcing custody | State | Reason / actual limit |
|---|---|---|---|
| Arc v2 EOA-signed PAY | ArcAccount | Local + authorized testnet proof suite | Singleton token/recipient/adapter; fixed-period and total caps, nonce, pause/revoke |
| Issuance | Controller threshold | Implemented | No separate delegated issuer aggregate scope in this release |
| Permissionless relay | ArcAccount + any gas payer | Implemented | Sponsorship only; reimbursement must be zero |
| Source CCTP intent | None in new source account | BLOCKED | Diagnostic unsigned burn preparation is not an enforced BRIDGE adapter |
| CCTP source attestation | Circle protocol, not this receiver | BLOCKED | No destination raw-message attestation/mint verifier; JSON is never authority |
| IntentVault release | ArcAccount + immutable per-intent vault | Custody only | Exact committed action and immutable recovery address; donation/mint indistinguishable |
| Global quota | Separate same-chain allocator prototype | PARTIAL | Local conservation and closure are atomic; not wired into ArcAccount expenditure |
| Cross-chain quota sync | None | BLOCKED | No authenticated final remote closure proof; no timeout-based reclaim or HTTP ack |
| SWAP | No verified Arc adapter | BLOCKED | No approved immutable router/upstream identity/floor route in this release |
| ESCROW_FUND | No verified escrow adapter | BLOCKED | No nominated independently reviewed escrow ABI/target; arbitrary CALL rejected |
| Circle developer EOA | Separate Amane custody only | Unverified provider adapter | Signing does not constrain external EOA funds |
| Circle user wallet | User-controlled signer | BLOCKED / not configured | No credentials/provider entitlement or runtime integration verified |
| Circle SCA / ERC1271 | Potential external signature validator | BLOCKED | Contract signature validation not implemented; no ecrecover equivalence claim |
| Safe / ERC7579 | Potential module or controller | BLOCKED | No module installation/version/license/deployment integration verified |
| Sui v1 / Sepolia v1 | Existing contracts | Regression tested | Domain and original code unchanged; no v2 Move compiler translation claim |

Compiler omission is prohibited. Unsupported clauses reject instead of compiling to a weaker rule. Changing root policy requires a fresh threshold-signed version; a model cannot expand scope. Root total resets only on explicit newly signed root version. Fixed periods may allow spending near either side of the boundary; they are not rolling windows. Threshold compromise is outside the threat model.

The source-map-js high advisory is confined to the existing dev-tool dependency graph (Vitest -> Vite -> PostCSS). No new runtime dependency imports it. Preserve the finding; do not characterize the advisory as resolved.

Contract event observation requires vetted code identity, canonical receipt and explicit downstream confirmation/reorg handling. Local JSON shape matching is always unauthenticated. No professional security audit, universal wallet compatibility or mainnet readiness is claimed.

## Full authority v3 local candidate (package 0.3.0)

The table above describes the archived deployed v2 subset. Version3 adds isolated modules and separate SDK subpaths; it does not change v2 deployments or v1 Sui/Sepolia sources.

| Candidate path | Enforcing implementation | Current evidence / limit |
|---|---|---|
| Multi-asset/recipient root, delegated issuer leases | ArcAuthority + pinned extension | Local tests; root/lease/issuer per-action, fixed epoch and lifetime debit |
| Bounded fee sponsorship | Owner FeePolicy + agent FeeIntent | Local tests; exact pinned recipient, combined principal/fee caps, measured Arc18→ERC20 6 conversion |
| CCTP source | CctpSourceAdapter called only by named enforcing source account | Local fixtures; exact burn, immutable route/minimum/fee, hook source action+destination spec |
| CCTP mint/custody | Per-destination-spec CREATE2 CctpReceivingVault + pinned MessageTransmitter | Local fixtures; actual raw attestation verifier call and exact mint delta; real Circle evidence unavailable |
| Global quota | GlobalQuotaRoot + EndpointQuota + atomic authority spend hook | Local grant/freeze/ACK and fuzz tests; sticky after first binding; before first binding not global |
| Authenticated quota sync | Finalized MessageTransmitter callback from exact root/leaf domain/address | Local bus fixture; no HTTP ack, no timeout reclaim; provider attesters/governance trusted |
| ESCROW_FUND | Immutable account/token/deal/target adapter, measured protocol credit and tokens | Local named Amane escrow ABI only; external provider target remains unconfigured |
| SWAP | Full account owner floor + exact input/output measurements | Local fixture router only; approved live immutable route remains unavailable |
| Circle user/SCA, Safe/ERC7579, Sui continuity route | No new integration | Remains unavailable until explicit provider/version/credential/runtime proof |

Provider proxy runtime identity does not freeze its governance or implementation. Source and destination account code, route adapter/vault immutables and token/provider identities must be checked in the deployment manifest. Transport provenance is valid only when the immutable source account is the enforcing ArcAuthority. Preserve old-policy route adapter registration for in-flight recovery. Destination budgets independently count destination execution; global economic accounting requires one canonical asset/budget mapping and explicitly bound quota grants.

New v3 testnet deployments, Sepolia burns and quota messages are outside the restricted v2 approval. No claim of live v3 CCTP or remote quota finality may be inferred from these fixtures.
