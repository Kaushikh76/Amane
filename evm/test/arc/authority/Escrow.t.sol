// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {AmaneTestToken} from "../../../src/AmaneTestToken.sol";
import {EscrowFundAdapter} from "../../../src/arc/adapters/EscrowFundAdapter.sol";
import "../../../src/AmaneTypes.sol";
contract EscrowFixture {
 AmaneTestToken immutable token;bool public creditEnabled=true;mapping(bytes32=>mapping(address=>uint256)) public funded;
 constructor(AmaneTestToken token_){token=token_;}
 function setCredit(bool enable) external {creditEnabled=enable;}
 function fund(bytes32 deal,address payer,uint256 amount) external {token.transferFrom(msg.sender,address(this),amount);if(creditEnabled)funded[deal][payer]+=amount;}
}
contract AuthorityEscrowTest is AuthorityBase {
 EscrowFixture escrow;bytes32 escrowId;bytes32 constant DEAL=keccak256("fixture-deal");
 function setUp() public override {super.setUp();escrow=new EscrowFixture(usd);escrowId=registry.register(address(new EscrowFundAdapter(address(acct),address(usd),address(escrow),DEAL)));RootPolicy memory p=_policy(1);p.allowedActions|=1<<11;p.endpoints[0].adapters=new AdapterRef[](1);p.endpoints[0].adapters[0]=AdapterRef(escrowId,"Amane Escrow Fund",3);p.endpoints[0].recipients=new Recipient[](1);p.endpoints[0].recipients[0]=Recipient(a32(address(escrow)),"Pinned escrow");_install(p);AgentLease memory l=_lease(ctrlA);l.allowedActions=1<<11;l.endpoints[0].adapters=new bytes32[](1);l.endpoints[0].adapters[0]=escrowId;l.endpoints[0].recipients=new bytes32[](1);l.endpoints[0].recipients[0]=a32(address(escrow));_activate(l,pkA);}
 function _fund(uint64 nonce) internal view returns(ActionIntent memory a){a=_pay(nonce,1_000000);a.actionKind=11;a.adapterId=escrowId;a.adapterName="Amane Escrow Fund";a.adapterVersion=3;a.recipient=a32(address(escrow));a.recipientLabel="Pinned escrow";}
 function test_escrow_fund_measures_credit_and_token_custody() public {_exec(_fund(1));assertEq(escrow.funded(DEAL,address(acct)),1_000000);assertEq(usd.balanceOf(address(escrow)),1_000000);}
 function test_token_delivery_without_escrow_credit_reverts_everything() public {escrow.setCredit(false);ActionIntent memory a=_fund(1);bytes memory sig=_agentSig(a);vm.expectRevert("FUND_NOT_EXACT");acct.executeAction(a,sig);assertEq(usd.balanceOf(address(escrow)),0);assertFalse(acct.nonceUsed(leaseId,1));}
 function test_changed_escrow_runtime_is_rejected() public {vm.etch(address(escrow),hex"00");ActionIntent memory a=_fund(1);bytes memory sig=_agentSig(a);vm.expectRevert();acct.executeAction(a,sig);assertFalse(acct.nonceUsed(leaseId,1));}
}
