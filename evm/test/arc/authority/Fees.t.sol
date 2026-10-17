// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {AuthorityFees} from "../../../src/arc/authority/AuthorityFees.sol";
import {ActionIntent} from "../../../src/AmaneTypes.sol";
contract AuthorityFeesTest is AuthorityBase {
 function setUp() public override {super.setUp();_ready();vm.txGasPrice(1e12);}
 function _feePolicy() internal view returns(AuthorityFees.Policy memory){return AuthorityFees.Policy(acct.policyHash(),leaseId,address(usd),executor,100,200,300,3600,1000000,1e12,0,uint64(T0+300));}
 function _installFee(AuthorityFees.Policy memory p) internal {acct.installFeePolicy(p,_both(acct.signingDigest(AuthorityFees.hash(p))));}
 function _fee(ActionIntent memory a,uint256 amount) internal view returns(AuthorityFees.Intent memory f,bytes memory sig){f=AuthorityFees.Intent(this.hAction(a),AuthorityFees.hash(_feePolicy()),amount);sig=_sign(pkAgent,acct.signingDigest(AuthorityFees.hash(f)));}
 function test_bounded_fee_exact_and_replay_reverts() public {_installFee(_feePolicy());ActionIntent memory a=_pay(1,1_000000);(AuthorityFees.Intent memory f,bytes memory sig)=_fee(a,100);bytes memory aSig=_agentSig(a);vm.prank(executor);acct.executeActionWithFee(a,aSig,f,sig);assertEq(usd.balanceOf(executor),100);assertEq(usd.balanceOf(merchant),1_000000);vm.prank(executor);vm.expectRevert();acct.executeActionWithFee(a,aSig,f,sig);assertEq(usd.balanceOf(executor),100);}
 function test_fee_over_cap_reverts_principal_and_nonce() public {_installFee(_feePolicy());ActionIntent memory a=_pay(1,1_000000);(AuthorityFees.Intent memory f,bytes memory sig)=_fee(a,101);bytes memory aSig=_agentSig(a);vm.prank(executor);vm.expectRevert("FEE_CAP");acct.executeActionWithFee(a,aSig,f,sig);assertEq(usd.balanceOf(merchant),0);assertFalse(acct.nonceUsed(leaseId,1));}
 function test_fee_recipient_and_amount_cannot_be_mutated() public {_installFee(_feePolicy());ActionIntent memory a=_pay(1,1_000000);(AuthorityFees.Intent memory f,bytes memory sig)=_fee(a,1);bytes memory aSig=_agentSig(a);vm.prank(attacker);vm.expectRevert("WRONG_FEE_INTENT");acct.executeActionWithFee(a,aSig,f,sig);f.amount=2;vm.prank(executor);vm.expectRevert("FEE_AGENT");acct.executeActionWithFee(a,aSig,f,sig);}
 function test_fee_never_exceeds_observed_gas_cost() public {_installFee(_feePolicy());vm.txGasPrice(0);ActionIntent memory a=_pay(1,1_000000);(AuthorityFees.Intent memory f,bytes memory sig)=_fee(a,1);bytes memory aSig=_agentSig(a);vm.prank(executor);vm.expectRevert("UNMEASURED_FEE");acct.executeActionWithFee(a,aSig,f,sig);assertFalse(acct.nonceUsed(leaseId,1));assertEq(usd.balanceOf(merchant),0);}
 function test_combined_principal_and_fee_share_per_action_cap() public {_installFee(_feePolicy());ActionIntent memory a=_pay(1,25_000000);(AuthorityFees.Intent memory f,bytes memory sig)=_fee(a,1);bytes memory aSig=_agentSig(a);vm.prank(executor);vm.expectRevert("COMBINED_ACTION_CAP");acct.executeActionWithFee(a,aSig,f,sig);assertFalse(acct.nonceUsed(leaseId,1));}
 function test_any_relayer_can_execute_without_claiming_fee() public {_installFee(_feePolicy());ActionIntent memory a=_pay(1,1_000000);bytes memory sig=_agentSig(a);vm.prank(attacker);acct.executeAction(a,sig);assertEq(usd.balanceOf(merchant),1_000000);assertEq(usd.balanceOf(attacker),0);}
}
