# Primary sources checked during implementation

2026-10-17. These establish documented interfaces, not deployed Amane proof.

- https://docs.sui.io/getting-started/onboarding/sui-install — CLI installation and version selection. Homebrew 1.81.1 executes all 126 unchanged Move tests.
- https://docs.arc.io/arc/references/connect-to-arc — 5042002, rpc.testnet.arc.io, native 18-decimal USDC, native/ERC20 are one economic balance.
- https://developers.circle.com/stablecoins/usdc-contract-addresses — chain-scoped ERC20 addresses, verify runtime decimals and identity.
- https://developers.circle.com/cctp/references/contract-addresses — testnet TokenMessengerV2 and MessageTransmitterV2 addresses; domain 0 Sepolia and 26 Arc.
- https://developers.circle.com/cctp/references/contract-interfaces — depositForBurnWithHook accepts arbitrary metadata; an attestation is not proof of arbitrary relayer JSON. The receiving app must validate authenticated raw message and its actual mint.

CCTP package currently prepares calldata and binds a diagnostic commitment. It does not submit burns, verify Circle signatures or implement a source-account BRIDGE adapter. IntentVault supplies isolated custody with exact signed action checks and threshold recovery. Any claim of authenticated source intent remains UNAVAILABLE. No Circle credentials are required for local SDK tests.
