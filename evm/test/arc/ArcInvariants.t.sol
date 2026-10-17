// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {ArcAccount} from "../../src/arc/ArcAccount.sol";
import {ArcTypes as T} from "../../src/arc/ArcTypes.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {TransferPayAdapter} from "../../src/adapters/TransferPayAdapter.sol";
import {AmaneTestToken} from "../../src/AmaneTestToken.sol";
contract ArcHandler is Test {
 ArcAccount public account;T.ActionIntent private last;bytes private lastSig;
 uint256 public nextNonce;uint256 public escaped;uint256 public replayed;uint256 public successfulAmount;
 address immutable owner;bytes32 immutable adapterId;address immutable token;address immutable recipient;
 constructor(ArcAccount a,address owner_,address token_,address recipient_,bytes32 id){account=a;owner=owner_;token=token_;recipient=recipient_;adapterId=id;}
 function spend(uint256 amount,bool redirect) external {
  amount=bound(amount,1,15);T.ActionIntent memory x=T.ActionIntent(bytes32("lease"),nextNonce++,9,token,redirect?address(0xbad):recipient,adapterId,amount,2000,0,address(0),bytes32("plan"));
  (uint8 v,bytes32 r,bytes32 s)=vm.sign(0x222,account.actionHash(x));bytes memory sig=abi.encodePacked(r,s,v);bool forbidden=redirect || !account.leaseLive(x.leaseId);
  try account.execute(x,sig){successfulAmount+=amount;last=x;lastSig=sig;if(forbidden)++escaped;}catch{}
 }
 function replay() external {if(lastSig.length==0)return;try account.execute(last,lastSig){++replayed;}catch{}}
 function pause() external {vm.prank(owner);account.pause();}
 function revoke() external {vm.prank(owner);account.revoke(bytes32("lease"));}
 function advance(uint256 seconds_) external {vm.warp(block.timestamp+bound(seconds_,0,100));}
}
contract ArcInvariants is Test {
 ArcAccount account;ArcHandler handler;AmaneTestToken token;bytes32 rootBucket;
 function setUp() public {
  vm.chainId(31337);vm.warp(1000);AdapterRegistry registry=new AdapterRegistry();TransferPayAdapter adapter=new TransferPayAdapter();bytes32 id=registry.register(address(adapter));
  address[] memory owners=new address[](1);owners[0]=vm.addr(0x111);account=new ArcAccount(owners,1,registry);token=new AmaneTestToken("Fixture","USD",6);
  T.RootPolicy memory p=T.RootPolicy(1,address(token),address(0x777),id,address(0x888),20,40,100,100,1000);
  bytes32 rootHash=account.policyHash(p);bytes[] memory sigs=new bytes[](1);(uint8 v,bytes32 r,bytes32 s)=vm.sign(0x111,account.controlHash(rootHash,address(account),3000));sigs[0]=abi.encodePacked(r,s,v);account.installPolicy(p,3000,sigs);
  T.AgentLease memory l=T.AgentLease(bytes32("lease"),rootHash,vm.addr(0x222),1000,2000,10,30,80);(v,r,s)=vm.sign(0x111,account.leaseHash(l));sigs[0]=abi.encodePacked(r,s,v);account.activateLease(l,sigs);token.mint(address(account),1000);
  rootBucket=keccak256(abi.encode("root",rootHash));handler=new ArcHandler(account,owners[0],address(token),address(0x777),id);targetContract(address(handler));
 }
 function invariant_no_recipient_or_pause_revocation_escape() public view {assertEq(handler.escaped(),0);assertEq(token.balanceOf(address(0xbad)),0);}
 function invariant_replay_never_executes() public view {assertEq(handler.replayed(),0);}
 function invariant_principal_conserved() public view {assertEq(token.balanceOf(address(account))+token.balanceOf(address(0x777)),1000);}
 function invariant_measured_pay_matches_expenditure() public view {assertEq(token.balanceOf(address(0x777)),handler.successfulAmount());assertEq(account.totalSpent(rootBucket),handler.successfulAmount());}
 function invariant_root_and_lease_totals_hold() public view {assertLe(handler.successfulAmount(),80);assertLe(account.totalSpent(rootBucket),100);}
 function invariant_root_period_cap_holds() public view {assertLe(account.periodSpent(rootBucket,block.timestamp/100),40);}
 function invariant_account_has_no_external_allowance() public view {assertEq(token.allowance(address(account),address(handler)),0);}
}
