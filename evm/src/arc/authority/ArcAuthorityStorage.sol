// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityFees} from "./AuthorityFees.sol";
import {AmaneStorage} from "../../AmaneStorage.sol";
/// Original layout preserved as a prefix; both account and pinned extension inherit this same layout.
abstract contract ArcAuthorityStorage is AmaneStorage {
    mapping(uint64=>mapping(bytes32=>bool)) internal policyEndpoints;
    mapping(uint64=>mapping(bytes32=>bool)) internal policyDestinations;
    struct QuotaBinding {address leaf;bytes32 grantId;bytes32 codeHash;}
    mapping(uint64=>mapping(bytes32=>QuotaBinding)) public quotaBindings;
    mapping(bytes32=>bool) public quotaRequired;
    struct FeeState {AuthorityFees.Policy policy;bytes32 hash;uint256 periodSpent;uint256 totalSpent;uint64 period;}
    mapping(bytes32=>FeeState) internal feePolicies;
}
