// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
library AuthorityFees {
 struct Policy {bytes32 rootHash;bytes32 leaseId;address token;address recipient;uint256 perAction;uint256 perPeriod;uint256 total;uint64 periodSeconds;uint256 maxGasUnits;uint256 maxGasPrice;uint64 nonce;uint64 deadline;}
 struct Intent {bytes32 actionDigest;bytes32 feePolicyHash;uint256 amount;}
 bytes32 internal constant POLICY_TYPEHASH=keccak256("FeePolicy(bytes32 rootHash,bytes32 leaseId,address token,address recipient,uint256 perAction,uint256 perPeriod,uint256 total,uint64 periodSeconds,uint256 maxGasUnits,uint256 maxGasPrice,uint64 nonce,uint64 deadline)");
 bytes32 internal constant INTENT_TYPEHASH=keccak256("FeeIntent(bytes32 actionDigest,bytes32 feePolicyHash,uint256 amount)");
 function hash(Policy memory p) internal pure returns(bytes32){return keccak256(abi.encode(POLICY_TYPEHASH,p));}
 function hash(Intent memory i) internal pure returns(bytes32){return keccak256(abi.encode(INTENT_TYPEHASH,i));}
}
