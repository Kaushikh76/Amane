# Full authority port after restricted PAY proof

Status: implementation in progress; no new broadcast authorized.

The deployed ArcAccount v2 admits one recipient/asset and threshold-issued leases. It did not complete the original root/issuer/compiler mandate. The existing Amane v1 account already implements multi-endpoint/asset/recipient policies and issuer caps; reusing that implementation is safer than recreating those checks around the reduced v2 shape.

Port the original account and pinned extension into separate ArcAuthority modules. Preserve all original files and existing ArcAccount v2 bytecode/schema. Reuse canonical v1 struct hashing and storage prefix, but use a new explicit EIP-712 domain `Amane Arc`, version `3`, chainId and verifyingContract. This deliberately prevents v1/v2/v3 signature replay. Expose the new compiler under a versioned subpath, without changing the frozen 0.2.0 interface handoff.

Changes from the original account are explicit: fixed epoch caps (not linear-refill token buckets); supported action mask PAY/SWAP/BRIDGE/ESCROW_FUND; exact sender/recipient measurements; issuer limits bounded by the live root; authenticated receiving paths verify registered source endpoints and current policy/lease version, using the source domain for source signatures. CCTP/escrow/reimbursement additions require their own executable tests and independent critic review. No deployment of the new source is included in the completed restricted-PAY approval.
