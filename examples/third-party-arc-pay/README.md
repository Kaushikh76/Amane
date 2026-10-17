# Standalone Amane PAY proof

From a fresh clone, `npm ci && npm run build`, then `node examples/third-party-arc-pay/verify.mjs` verifies the recorded Arc contract codehash, permitted PAY event and actual reverted redirect transaction. This is read-only; no key or Synq checkout is needed. Contract source is unaudited and testnet-only.

For independent deployment and execution without any faucet/key setup, start silent local Anvil and run `node scripts/continuity/local-proof.mjs`. That script imports the published package exports and demonstrates owner-issued policy/lease, a separate unfunded agent, unrelated funded relayer, exact payment, malicious alternative and journal restart.

The new public package API is `@amane/policy` (strict compiler + EIP-712), `@amane/arc` (registry/artifacts/client/journal), `@amane/verify` (code and canonical receipt observation), `@amane/cctp` (unsigned diagnostic source-commitment preparation only). Existing `@amane/core` and `@amane/sdk` v1 are unchanged. Local tarballs and SHA256s are in the release handoff; no npm publication is required.

A developer creating their own live account must arrange their own explicit testnet budget and signing roles and inspect exact deployment bytecode/constructor args. The owner-specific broadcast script and its file paths are not a general adoption requirement. Do not fund mainnet, import the deterministic local fixture keys into a real wallet, or claim CCTP/global quota support from the PAY example.
