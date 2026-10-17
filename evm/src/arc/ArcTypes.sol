// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library ArcTypes {
    // Restricted first release: one asset, recipient and immutable PAY adapter per root.
    struct RootPolicy {
        uint64 version; address token; address recipient; bytes32 adapterId; address recovery;
        uint256 perAction; uint256 perPeriod; uint256 total; uint64 periodSeconds; uint64 maxLeaseLifetime;
    }
    struct AgentLease {
        bytes32 leaseId; bytes32 rootHash; address agent; uint64 validAfter; uint64 expiresAt;
        uint256 perAction; uint256 perPeriod; uint256 total;
    }
    struct ActionIntent {
        bytes32 leaseId; uint256 nonce; uint8 kind; address token; address recipient; bytes32 adapterId;
        uint256 amount; uint64 deadline; uint256 maxFee; address feeRecipient; bytes32 planHash;
    }
    bytes32 internal constant ROOT_TYPEHASH = keccak256("RootPolicy(uint64 version,address token,address recipient,bytes32 adapterId,address recovery,uint256 perAction,uint256 perPeriod,uint256 total,uint64 periodSeconds,uint64 maxLeaseLifetime)");
    bytes32 internal constant LEASE_TYPEHASH = keccak256("AgentLease(bytes32 leaseId,bytes32 rootHash,address agent,uint64 validAfter,uint64 expiresAt,uint256 perAction,uint256 perPeriod,uint256 total)");
    bytes32 internal constant ACTION_TYPEHASH = keccak256("ActionIntent(bytes32 leaseId,uint256 nonce,uint8 kind,address token,address recipient,bytes32 adapterId,uint256 amount,uint64 deadline,uint256 maxFee,address feeRecipient,bytes32 planHash)");
    bytes32 internal constant CONTROL_TYPEHASH = keccak256("Control(bytes32 operation,address target,uint256 nonce,uint64 deadline)");
    function hash(RootPolicy memory x) internal pure returns(bytes32) { return keccak256(abi.encode(ROOT_TYPEHASH,x)); }
    function hash(AgentLease memory x) internal pure returns(bytes32) { return keccak256(abi.encode(LEASE_TYPEHASH,x)); }
    function hash(ActionIntent memory x) internal pure returns(bytes32) { return keccak256(abi.encode(ACTION_TYPEHASH,x)); }
}
