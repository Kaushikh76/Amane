// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {RootPolicy,AgentLease,ActionIntent,Recipient,AssetLimit,AmaneHash,RevokeLease} from "../../../src/AmaneTypes.sol";
import {ArcAuthorityFactory} from "../../../src/arc/authority/ArcAuthorityFactory.sol";
import {AmaneStorage} from "../../../src/AmaneStorage.sol";
import {Codes} from "../../../src/AmaneCodes.sol";
contract FullAuthorityTest is AuthorityBase {
    using AmaneHash for *;
    function test_multi_recipient_lease_is_subset_and_enforced() public {
        RootPolicy memory p=_policy(1);Recipient[] memory xs=new Recipient[](2);xs[0]=p.endpoints[0].recipients[0];xs[1]=Recipient(a32(attacker),"Explicitly approved second recipient");p.endpoints[0].recipients=xs;_install(p);
        AgentLease memory l=_lease(ctrlA);l.endpoints[0].recipients=new bytes32[](2);l.endpoints[0].recipients[0]=a32(merchant);l.endpoints[0].recipients[1]=a32(attacker);_activate(l,pkA);
        _exec(_pay(1,1_000000));ActionIntent memory a=_pay(2,1_000000);a.recipient=a32(attacker);a.recipientLabel="Explicitly approved second recipient";_exec(a);
        assertEq(usd.balanceOf(merchant),1_000000);assertEq(usd.balanceOf(attacker),1_000000);
        a.nonce=3;a.recipient=a32(recovery);_execReject(a,Codes.ACTION_RECIPIENT_NOT_ALLOWED);
    }
    function test_multi_asset_caps_are_separate_and_exact() public {
        RootPolicy memory p=_policy(1);p.endpoints[0].assets[1]=AssetLimit(a32(address(amsui)),1000,2000,5000);_install(p);
        AgentLease memory l=_lease(ctrlA);l.endpoints[0].assets[1]=AssetLimit(a32(address(amsui)),500,1000,2000);_activate(l,pkA);amsui.mint(address(acct),1000);
        ActionIntent memory a=_pay(1,500);a.assetIn=a32(address(amsui));a.assetOut=a.assetIn;_exec(a);assertEq(amsui.balanceOf(merchant),500);assertEq(usd.balanceOf(merchant),0);
        a.nonce=2;a.amountIn=501;_execReject(a,Codes.BUDGET_PER_ACTION);assertFalse(acct.nonceUsed(leaseId,2));
    }
    function test_issuer_cannot_allocate_more_than_root_or_self() public {
        _install(_policy(1));AgentLease memory l=_lease(issuer);l.endpoints[0].assets[0].maxPerAction=51_000000;_activateReject(l,pkIssuer,Codes.LEASE_CAP_EXCEEDS_ISSUER);
        l=_lease(issuer);l.agent=attacker;_activateReject(l,pkIssuer,Codes.LEASE_AGENT_NOT_ALLOWED);
    }
    function test_concurrent_issuer_leases_share_period_and_total() public {
        _install(_policy(1));AgentLease memory first=_lease(issuer);_activate(first,pkIssuer);_exec(_pay(1,25_000000));_exec(_pay(2,25_000000));
        leaseId=keccak256("second");_activate(_lease(issuer),pkIssuer);_exec(_pay(1,25_000000));_exec(_pay(2,25_000000));
        leaseId=keccak256("third");_activate(_lease(issuer),pkIssuer);_execReject(_pay(1,1),Codes.BUDGET_EPOCH);
        vm.warp(T0+3600);_execReject(_pay(1,1),Codes.BUDGET_TOTAL);assertFalse(acct.nonceUsed(leaseId,1));
        (,AmaneStorage.Spend memory spent)=acct.rootBudget(a32(address(usd)));assertEq(spent.totalSpent,100_000000);
    }
    function test_fixed_period_does_not_refill_halfway() public {
        _ready();_exec(_pay(1,25_000000));_exec(_pay(2,25_000000));vm.warp(T0+1800);_execReject(_pay(3,1),Codes.BUDGET_EPOCH);
        vm.warp(T0+3600);ActionIntent memory a=_pay(3,1_000000);a.deadline=uint64(T0+3900);_exec(a);assertEq(usd.balanceOf(merchant),51_000000);
    }
    function test_swap_owner_floor_and_exact_measurement() public {
        _ready();assertEq(_exec(_swap(1,1_000000,950_000000)),1000_000000);
        _execReject(_swap(2,1_000000,1001_000000),Codes.ACTION_BELOW_MIN_OUT);
        ActionIntent memory a=_swap(2,1_000000,0);a.recipient=a32(attacker);_execReject(a,Codes.ACTION_RECIPIENT_NOT_ALLOWED);
    }
    function oldPolicyDigest(RootPolicy calldata p) external pure returns(bytes32) {return AmaneHash.digest(p.hash());}
    function test_v1_domain_cannot_install_v3_policy() public {RootPolicy memory p=_policy(1);bytes[] memory ss=_both(this.oldPolicyDigest(p));vm.expectRevert();acct.installPolicy(p,ss);assertEq(acct.policyVersion(),0);}
    function test_policy_revision_revocation_and_chain_cannot_be_bypassed() public {
        _ready();RevokeLease memory x=RevokeLease(ACCOUNT_ID,leaseId);acct.revokeLease(x,_sign(pkA,this.hRevoke(x)));_execReject(_pay(1,1),Codes.LEASE_NOT_ACTIVE);
        AgentLease memory l=_lease(ctrlA);_activateReject(l,pkA,Codes.REPLAY_LEASE_ID);
        leaseId=keccak256("fresh");_activate(_lease(ctrlA),pkA);_install(_policy(2));_execReject(_pay(1,1),Codes.POLICY_VERSION_MISMATCH);
    }
    function test_issuer_policy_itself_is_bounded_by_root() public {RootPolicy memory p=_policy(1);p.leaseIssuers[0].limits[0].maxTotal=501_000000;bytes[] memory ss=_both(this.hPolicy(p));vm.expectRevert();acct.installPolicy(p,ss);}
    function test_factory_pins_full_identity_and_extension() public {
        ArcAuthorityFactory f=new ArcAuthorityFactory(registry,acct.ext());address[] memory owners=_sorted(ctrlA,ctrlB);bytes32 salt=keccak256("factory");
        address predicted=f.predict(ACCOUNT_ID,owners,2,salt);assertEq(predicted,f.create(ACCOUNT_ID,owners,2,salt));assertEq(predicted,f.create(ACCOUNT_ID,owners,2,salt));assertNotEq(predicted,f.predict(keccak256("other"),owners,2,salt));
        vm.etch(acct.ext(),hex"00");vm.expectRevert();f.create(ACCOUNT_ID,owners,2,keccak256("different"));
    }
    function test_factory_rejects_mutated_creation_code_store() public {ArcAuthorityFactory f=new ArcAuthorityFactory(registry,acct.ext());vm.etch(f.codeFirst(),hex"00");address[] memory owners=_sorted(ctrlA,ctrlB);vm.expectRevert("CREATION_CODE_CHANGED");f.create(ACCOUNT_ID,owners,2,keccak256("tamper"));}

}
