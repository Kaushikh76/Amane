// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {GlobalQuotaRoot} from "../../../src/arc/quota/GlobalQuotaRoot.sol";
import {EndpointQuota} from "../../../src/arc/quota/EndpointQuota.sol";
import {QuotaTypes} from "../../../src/arc/quota/QuotaSync.sol";
import {ArcAuthorityDomain as Domain} from "../../../src/arc/authority/ArcAuthorityDomain.sol";
import {ActionIntent,AgentLease} from "../../../src/AmaneTypes.sol";
interface IQuotaHandlerFixture {function handleReceiveFinalizedMessage(uint32,bytes32,uint32,bytes calldata) external returns(bool);}
/// In-memory message bus fixture: preserves actual emitted sender/body and simulates finalized delivery.
/// This is not a Circle attestation or a live cross-chain proof.
contract QuotaBusFixture {
 struct Message {uint32 sourceDomain;bytes32 sender;address recipient;bytes body;}
 address immutable fixtureOwner=msg.sender;mapping(address=>uint32) domains;Message[] private messages;
 function setDomain(address sender,uint32 domain) external {require(msg.sender==fixtureOwner);domains[sender]=domain;}
 function sendMessage(uint32,bytes32 recipient,bytes32,uint32 finality,bytes calldata body) external {require(finality==2000);messages.push(Message(domains[msg.sender],bytes32(uint256(uint160(msg.sender))),address(uint160(uint256(recipient))),body));}
 function deliver(uint256 index) external {Message memory m=messages[index];require(IQuotaHandlerFixture(m.recipient).handleReceiveFinalizedMessage(m.sourceDomain,m.sender,2000,m.body));}
 function count() external view returns(uint256){return messages.length;}
}
contract AuthorityQuotaTest is AuthorityBase {
 using QuotaTypes for QuotaTypes.Grant;
 QuotaBusFixture bus;GlobalQuotaRoot root;EndpointQuota leaf;bytes32 constant BUDGET_ASSET=keccak256("USDC six decimal budget");
 function setUp() public override {super.setUp();_ready();bus=new QuotaBusFixture();address[] memory owners=new address[](1);owners[0]=ctrlA;root=new GlobalQuotaRoot(address(bus),acct.policyHash(),BUDGET_ASSET,100_000000,50_000000,3600,600,owners,1);leaf=new EndpointQuota(address(bus),address(root),26,address(acct),acct.chainRef(),acct.policyHash(),BUDGET_ASSET);bus.setDomain(address(root),26);bus.setDomain(address(leaf),0);}
 function _grant(uint64 nonce,uint256 amount) internal view returns(QuotaTypes.Grant memory){return QuotaTypes.Grant(acct.policyHash(),BUDGET_ASSET,acct.chainRef(),address(acct),uint64(T0/3600),nonce,uint64(T0+300),amount);}
 function _signRoot(bytes32 h) internal view returns(bytes[] memory ss){ss=new bytes[](1);ss[0]=_sign(pkA,Domain.at(h,31337,address(root)));}
 function _allocate(QuotaTypes.Grant memory g) internal returns(bytes32){return root.allocate(g,address(leaf),0,_signRoot(root.allocationHash(g,address(leaf),0)));}
 function _bind(bytes32 id) internal {bytes32 h=keccak256(abi.encode(keccak256("BindQuota(bytes32 policyHash,bytes32 localAsset,bytes32 budgetAsset,address leaf,bytes32 grantId,uint64 nonce,uint64 deadline)"),acct.policyHash(),a32(address(usd)),BUDGET_ASSET,address(leaf),id,uint64(0),uint64(T0+300)));acct.bindQuota(a32(address(usd)),BUDGET_ASSET,address(leaf),id,0,uint64(T0+300),_both(acct.signingDigest(h)));}
 function test_authority_spend_consumes_global_quota_atomically() public {bytes32 id=_allocate(_grant(0,30_000000));bus.deliver(0);_bind(id);_exec(_pay(1,25_000000));ActionIntent memory a=_pay(2,6_000000);bytes memory sig=_agentSig(a);vm.expectRevert("QUOTA_EXCEEDED");acct.executeAction(a,sig);assertFalse(acct.nonceUsed(leaseId,2));(,uint256 spent,,,)=leaf.balances(id);assertEq(spent,25_000000);assertEq(usd.balanceOf(merchant),25_000000);}
 function test_reclaim_requires_authenticated_freeze_ack_and_never_reuses_spend() public {bytes32 id=_allocate(_grant(0,30_000000));bus.deliver(0);_bind(id);_exec(_pay(1,25_000000));root.requestFreeze(id,_signRoot(root.freezeHash(id)));assertEq(root.free(),70_000000);bus.deliver(1);assertEq(root.free(),70_000000);bus.deliver(2);assertEq(root.free(),75_000000);assertEq(root.finalizedSpent(),25_000000);assertEq(root.outstanding(),0);vm.expectRevert();bus.deliver(2);assertEq(root.free(),75_000000);}
 function test_expiry_never_implicitly_frees_quota() public {_allocate(_grant(0,30_000000));vm.warp(T0+3601);assertEq(root.outstanding(),30_000000);assertEq(root.free(),70_000000);}
 function test_freeze_delivered_before_grant_cannot_resurrect_authority() public {bytes32 id=_allocate(_grant(0,30_000000));root.requestFreeze(id,_signRoot(root.freezeHash(id)));bus.deliver(1);bus.deliver(2);assertEq(root.free(),100_000000);vm.expectRevert();bus.deliver(0);_bind(id);ActionIntent memory a=_pay(1,1);bytes memory sig=_agentSig(a);vm.expectRevert("QUOTA_EXCEEDED");acct.executeAction(a,sig);}
 function test_forged_ack_or_wrong_root_not_accepted() public {bytes32 id=_allocate(_grant(0,30_000000));vm.expectRevert("UNAUTHENTICATED_SYNC");root.handleReceiveFinalizedMessage(0,bytes32(uint256(uint160(address(leaf)))),2000,abi.encode(uint8(3),id,0));vm.expectRevert("UNAUTHENTICATED_SYNC");leaf.handleReceiveFinalizedMessage(26,bytes32(uint256(uint160(address(root)))),2000,abi.encode(uint8(2),id));assertEq(root.outstanding(),30_000000);}
 function test_duplicate_allocation_and_period_overallocation_rejected() public {QuotaTypes.Grant memory g=_grant(0,30_000000);_allocate(g);bytes[] memory sig=_signRoot(root.allocationHash(g,address(leaf),0));vm.expectRevert("WRONG_GRANT");root.allocate(g,address(leaf),0,sig);g=_grant(1,21_000000);sig=_signRoot(root.allocationHash(g,address(leaf),0));vm.expectRevert("GLOBAL_CAP");root.allocate(g,address(leaf),0,sig);assertEq(root.outstanding(),30_000000);}
 function testFuzz_spend_freeze_reclaim_conservation(uint256 amount) public {amount=bound(amount,1,25_000000);bytes32 id=_allocate(_grant(0,30_000000));bus.deliver(0);_bind(id);_exec(_pay(1,amount));root.requestFreeze(id,_signRoot(root.freezeHash(id)));assertEq(root.outstanding(),30_000000);bus.deliver(1);bus.deliver(2);assertEq(root.finalizedSpent(),amount);assertEq(root.free()+root.outstanding()+root.finalizedSpent(),100_000000);vm.expectRevert();bus.deliver(2);assertEq(root.free()+root.finalizedSpent(),100_000000);}
 function test_new_policy_cannot_drop_quota_mode() public {bytes32 id=_allocate(_grant(0,30_000000));bus.deliver(0);_bind(id);_install(_policy(2));leaseId=keccak256("new lease");AgentLease memory l=_lease(ctrlA);l.policyVersion=2;_activate(l,pkA);ActionIntent memory a=_pay(1,1);a.policyVersion=2;bytes memory sig=_agentSig(a);vm.expectRevert("QUOTA_BINDING_REQUIRED");acct.executeAction(a,sig);assertFalse(acct.nonceUsed(leaseId,1));}

}
