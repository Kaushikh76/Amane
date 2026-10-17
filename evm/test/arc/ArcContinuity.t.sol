// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {ArcAccount} from "../../src/arc/ArcAccount.sol";
import {ArcFactory} from "../../src/arc/ArcFactory.sol";
import {ArcTypes as T} from "../../src/arc/ArcTypes.sol";
import {IntentVault,IntentVaultFactory} from "../../src/arc/IntentVault.sol";
import {QuotaAllocator,QuotaLeaf} from "../../src/arc/QuotaAllocator.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {TransferPayAdapter} from "../../src/adapters/TransferPayAdapter.sol";
import {AmaneTestToken} from "../../src/AmaneTestToken.sol";
contract ArcContinuityTest is Test {
 ArcAccount a; ArcFactory f; AdapterRegistry r; TransferPayAdapter adapter; AmaneTestToken token;
 T.RootPolicy p; T.AgentLease l; uint256 ownerKey=0x111;uint256 agentKey=0x222;
 address recipient=address(0x777);address recovery=address(0x888);
 function setUp() public {
  vm.chainId(31337);vm.warp(1000);r=new AdapterRegistry();adapter=new TransferPayAdapter();bytes32 id=r.register(address(adapter));f=new ArcFactory(r);
  address[] memory owners=new address[](1);owners[0]=vm.addr(ownerKey);a=ArcAccount(f.create(owners,1,bytes32("test")));
  token=new AmaneTestToken("USDC fixture","USDC",6);p=T.RootPolicy(1,address(token),recipient,id,recovery,20,40,100,100,1000);install(p);
  l=T.AgentLease(bytes32("lease"),a.rootHash(),vm.addr(agentKey),1000,2000,10,30,80);activate(l);token.mint(address(a),1000);
 }
 function sig(uint256 k,bytes32 h) internal returns(bytes memory) {(uint8 v,bytes32 rr,bytes32 s)=vm.sign(k,h);return abi.encodePacked(rr,s,v);}
 function sigs(bytes32 h) internal returns(bytes[] memory ss) {ss=new bytes[](1);ss[0]=sig(ownerKey,h);}
 function install(T.RootPolicy memory x) internal {bytes[] memory ss=sigs(a.controlHash(a.policyHash(x),address(a),3000));a.installPolicy(x,3000,ss);}
 function activate(T.AgentLease memory x) internal {bytes[] memory ss=sigs(a.leaseHash(x));a.activateLease(x,ss);}
 function action(uint256 n,uint256 amount) internal view returns(T.ActionIntent memory) {return T.ActionIntent(l.leaseId,n,9,address(token),recipient,p.adapterId,amount,1900,0,address(0),bytes32("plan"));}
 function execute(T.ActionIntent memory x) internal {a.execute(x,sig(agentKey,a.actionHash(x)));}
 function reject(T.ActionIntent memory x) internal {bytes memory s=sig(agentKey,a.actionHash(x));vm.expectRevert();a.execute(x,s);assertFalse(a.nonceUsed(x.leaseId,x.nonce));}
 function test_pay_exact_nonce_race() public {T.ActionIntent memory x=action(1,10);bytes memory s=sig(agentKey,a.actionHash(x));vm.prank(address(1));a.execute(x,s);vm.expectRevert();vm.prank(address(2));a.execute(x,s);assertEq(token.balanceOf(recipient),10);assertEq(token.balanceOf(address(a)),990);}
 function test_compromised_agent_redirect() public {T.ActionIntent memory x=action(1,10);x.recipient=address(0xbad);reject(x);assertEq(token.balanceOf(address(0xbad)),0);}
 function test_relayer_tamper() public {T.ActionIntent memory x=action(1,10);bytes memory s=sig(agentKey,a.actionHash(x));x.amount=9;vm.expectRevert();a.execute(x,s);assertEq(token.balanceOf(recipient),0);}
 function test_all_budget_caps() public {reject(action(1,11));execute(action(1,10));execute(action(2,10));execute(action(3,10));reject(action(4,1));vm.warp(1100);execute(action(4,10));execute(action(5,10));execute(action(6,10));vm.warp(1200);execute(action(7,10));execute(action(8,10));reject(action(9,1));}
 function test_two_leases_share_root() public {T.AgentLease memory x=l;x.leaseId=bytes32("other");activate(x);execute(action(1,10));execute(action(2,10));execute(action(3,10));l=x;execute(action(1,10));reject(action(2,1));}
 function test_revoke_no_resurrection() public {vm.prank(vm.addr(ownerKey));a.revoke(l.leaseId);reject(action(1,1));bytes[] memory ss=sigs(a.leaseHash(l));vm.expectRevert();a.activateLease(l,ss);}
 function test_validity() public {vm.warp(999);reject(action(1,1));vm.warp(2001);reject(action(1,1));}
 function test_pause() public {vm.prank(vm.addr(ownerKey));a.pause();reject(action(1,1));}
 function test_stale_unpause() public {vm.prank(vm.addr(ownerKey));a.pause();bytes[] memory ss=sigs(a.controlHash(keccak256(abi.encode("UNPAUSE",a.pauseEpoch())),address(a),1900));vm.prank(vm.addr(ownerKey));a.pause();vm.expectRevert();a.unpause(1900,ss);}
 function test_fee_disabled() public {T.ActionIntent memory x=action(1,1);x.maxFee=1;reject(x);}
 function test_call_disabled() public {T.ActionIntent memory x=action(1,1);x.kind=255;reject(x);}
 function test_adapter_mutation() public {vm.etch(address(adapter),hex"00");reject(action(1,1));}
 function test_decimal_mismatch() public {T.RootPolicy memory x=p;x.version=2;x.token=address(new AmaneTestToken("Bad","BAD",18));bytes[] memory ss=sigs(a.controlHash(a.policyHash(x),address(a),3000));vm.expectRevert();a.installPolicy(x,3000,ss);}
 function test_chain_domain() public {T.ActionIntent memory x=action(1,1);bytes32 h=a.actionHash(x);bytes memory s=sig(agentKey,h);vm.chainId(5042002);vm.expectRevert();a.execute(x,s);assertNotEq(a.actionHash(x),h);}
 function test_policy_revision() public {p.version=2;install(p);reject(action(1,1));}
 function test_factory_idempotent_owner_bound() public {address[] memory owners=new address[](1);owners[0]=vm.addr(ownerKey);assertEq(f.predict(owners,1,bytes32("test")),address(a));assertEq(f.create(owners,1,bytes32("test")),address(a));owners[0]=address(0x123);assertNotEq(f.predict(owners,1,bytes32("test")),address(a));}
 function test_threshold() public {p.version=2;bytes[] memory ss=new bytes[](0);vm.expectRevert();a.installPolicy(p,3000,ss);}
 function test_vault_exact_once() public {T.ActionIntent memory x=action(1,10);IntentVault v=new IntentVault(a,x);token.mint(address(v),10);bytes memory s=sig(agentKey,a.actionHash(x));a.executeVault(x,s,address(v));assertEq(token.balanceOf(recipient),10);vm.expectRevert();a.executeVault(x,s,address(v));}
 function test_vault_plan_mismatch_donation() public {T.ActionIntent memory x=action(1,10);IntentVault v=new IntentVault(a,x);token.mint(address(v),10);x.planHash=bytes32("fake source");bytes memory s=sig(agentKey,a.actionHash(x));vm.expectRevert();a.executeVault(x,s,address(v));assertEq(token.balanceOf(address(v)),10);assertFalse(a.nonceUsed(x.leaseId,x.nonce));}
 function test_late_mint_revoked_recovery() public {T.ActionIntent memory x=action(1,10);IntentVault v=new IntentVault(a,x);vm.prank(vm.addr(ownerKey));a.revoke(x.leaseId);token.mint(address(v),10);bytes memory s=sig(agentKey,a.actionHash(x));vm.expectRevert();a.executeVault(x,s,address(v));assertTrue(v.quarantined());bytes[] memory ss=sigs(a.controlHash(keccak256("RECOVER_VAULT"),address(v),1900));a.recoverVault(address(v),1900,ss);assertEq(token.balanceOf(recovery),10);assertEq(token.balanceOf(recipient),0);}
 function test_no_early_recovery() public {IntentVault v=new IntentVault(a,action(1,10));token.mint(address(v),10);bytes[] memory ss=sigs(a.controlHash(keccak256("RECOVER_VAULT"),address(v),1900));vm.expectRevert();a.recoverVault(address(v),1900,ss);assertEq(token.balanceOf(address(v)),10);}
 function test_vault_factory_idempotent() public {IntentVaultFactory vf=new IntentVaultFactory();T.ActionIntent memory x=action(1,10);assertEq(vf.predict(a,x),vf.create(a,x));assertEq(vf.create(a,x),vf.predict(a,x));}
 function testFuzz_redirect(uint256 amount,address bad) public {vm.assume(bad!=recipient);T.ActionIntent memory x=action(1,bound(amount,1,100000));x.recipient=bad;reject(x);assertEq(token.balanceOf(recipient),0);}
 function test_quota_double_allocate_reclaim() public {QuotaAllocator q=new QuotaAllocator(100);QuotaLeaf leaf=q.allocate(bytes32("one"),address(this),60);vm.expectRevert();q.allocate(bytes32("two"),address(this),60);leaf.spend(20);q.reclaim(bytes32("one"));assertEq(q.free(),80);assertEq(q.finalizedSpent(),20);vm.expectRevert();q.reclaim(bytes32("one"));vm.expectRevert();leaf.spend(1);}
 function test_quota_forged_ack() public {QuotaAllocator q=new QuotaAllocator(100);QuotaLeaf leaf=q.allocate(bytes32("one"),address(this),50);vm.expectRevert();vm.prank(address(0xbad));leaf.close();assertEq(q.free(),50);}
 function testFuzz_quota_conservation(uint256 amount,uint256 spend) public {amount=bound(amount,1,100);spend=bound(spend,1,amount);QuotaAllocator q=new QuotaAllocator(100);QuotaLeaf leaf=q.allocate(bytes32("one"),address(this),amount);leaf.spend(spend);assertEq(q.free()+q.outstanding()+q.finalizedSpent(),100);q.reclaim(bytes32("one"));assertEq(q.free()+q.outstanding()+q.finalizedSpent(),100);assertEq(q.finalizedSpent(),spend);}
}
