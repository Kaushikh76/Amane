/// Cross-implementation parity for the Arc authority schemas (v2 restricted PAY and v3 full authority).
/// Additive: nothing here is referenced by the v1 account module, and the v1 domain
/// (`amane::eip712::domain_separator`) and all v1 behaviour are unchanged. Sui does not enforce Arc
/// authority; this module only proves the Move implementation reproduces the TS and Solidity hashes
/// byte-for-byte so a future Sui endpoint can verify Arc-signed material. Golden vectors:
/// vectors/arc-v2.json and vectors/authority-v3.json.
module amane::arc_eip712;

use amane::eip712;
use sui::hash::keccak256;

const EBadLength: u64 = 300;

const DOMAIN_T: vector<u8> = b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
const V2_ROOT_T: vector<u8> =
    b"RootPolicy(uint64 version,address token,address recipient,bytes32 adapterId,address recovery,uint256 perAction,uint256 perPeriod,uint256 total,uint64 periodSeconds,uint64 maxLeaseLifetime)";
const V2_LEASE_T: vector<u8> =
    b"AgentLease(bytes32 leaseId,bytes32 rootHash,address agent,uint64 validAfter,uint64 expiresAt,uint256 perAction,uint256 perPeriod,uint256 total)";
const V2_ACTION_T: vector<u8> =
    b"ActionIntent(bytes32 leaseId,uint256 nonce,uint8 kind,address token,address recipient,bytes32 adapterId,uint256 amount,uint64 deadline,uint256 maxFee,address feeRecipient,bytes32 planHash)";

fun b32(x: &vector<u8>) { assert!(x.length() == 32, EBadLength); }
fun b20(x: &vector<u8>) { assert!(x.length() == 20, EBadLength); }

fun word_address(a: &vector<u8>): vector<u8> {
    b20(a);
    let mut out = x"000000000000000000000000";
    out.append(*a);
    out
}

fun cat(parts: vector<vector<u8>>): vector<u8> {
    let mut out = vector[];
    parts.do!(|p| out.append(p));
    out
}

fun keccak_of(parts: vector<vector<u8>>): vector<u8> { keccak256(&cat(parts)) }

// ------------------------------------------------------------------ domains

/// `version` is b"2" for the restricted v2 account and b"3" for the full authority.
public fun domain_separator(version: vector<u8>, chain_id: u256, verifying_contract: &vector<u8>): vector<u8> {
    keccak_of(vector[
        keccak256(&DOMAIN_T),
        keccak256(&b"Amane Arc"),
        keccak256(&version),
        eip712::word_u256(chain_id),
        word_address(verifying_contract),
    ])
}

public fun digest(version: vector<u8>, chain_id: u256, verifying_contract: &vector<u8>, struct_hash: vector<u8>): vector<u8> {
    b32(&struct_hash);
    keccak256(&cat(vector[x"1901", domain_separator(version, chain_id, verifying_contract), struct_hash]))
}

/// Full authority (v3): shared v1 struct hashes (eip712::hash_*), new chain/account-bound domain.
public fun digest_v3(chain_id: u256, account: &vector<u8>, struct_hash: vector<u8>): vector<u8> {
    digest(b"3", chain_id, account, struct_hash)
}

// ------------------------------------------------------------------ v2 restricted PAY structs

public fun type_hash_v2_root(): vector<u8> { keccak256(&V2_ROOT_T) }
public fun type_hash_v2_lease(): vector<u8> { keccak256(&V2_LEASE_T) }
public fun type_hash_v2_action(): vector<u8> { keccak256(&V2_ACTION_T) }

public fun hash_v2_root(
    version: u64, token: &vector<u8>, recipient: &vector<u8>, adapter_id: &vector<u8>, recovery: &vector<u8>,
    per_action: u256, per_period: u256, total: u256, period_seconds: u64, max_lease_lifetime: u64,
): vector<u8> {
    b32(adapter_id);
    keccak_of(vector[
        type_hash_v2_root(),
        eip712::word_u256(version as u256),
        word_address(token),
        word_address(recipient),
        *adapter_id,
        word_address(recovery),
        eip712::word_u256(per_action),
        eip712::word_u256(per_period),
        eip712::word_u256(total),
        eip712::word_u256(period_seconds as u256),
        eip712::word_u256(max_lease_lifetime as u256),
    ])
}

public fun hash_v2_lease(
    lease_id: &vector<u8>, root_hash: &vector<u8>, agent: &vector<u8>, valid_after: u64, expires_at: u64,
    per_action: u256, per_period: u256, total: u256,
): vector<u8> {
    b32(lease_id);
    b32(root_hash);
    keccak_of(vector[
        type_hash_v2_lease(),
        *lease_id,
        *root_hash,
        word_address(agent),
        eip712::word_u256(valid_after as u256),
        eip712::word_u256(expires_at as u256),
        eip712::word_u256(per_action),
        eip712::word_u256(per_period),
        eip712::word_u256(total),
    ])
}

public fun hash_v2_action(
    lease_id: &vector<u8>, nonce: u256, kind: u8, token: &vector<u8>, recipient: &vector<u8>, adapter_id: &vector<u8>,
    amount: u256, deadline: u64, max_fee: u256, fee_recipient: &vector<u8>, plan_hash: &vector<u8>,
): vector<u8> {
    b32(lease_id);
    b32(adapter_id);
    b32(plan_hash);
    keccak_of(vector[
        type_hash_v2_action(),
        *lease_id,
        eip712::word_u256(nonce),
        eip712::word_u256(kind as u256),
        word_address(token),
        word_address(recipient),
        *adapter_id,
        eip712::word_u256(amount),
        eip712::word_u256(deadline as u256),
        eip712::word_u256(max_fee),
        word_address(fee_recipient),
        *plan_hash,
    ])
}
