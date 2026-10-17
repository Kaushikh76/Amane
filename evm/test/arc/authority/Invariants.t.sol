// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {Test} from "forge-std/Test.sol";
import {ArcAuthority} from "../../../src/arc/authority/ArcAuthority.sol";
import {AmaneStorage} from "../../../src/AmaneStorage.sol";
import {ActionIntent,PauseAccount,RevokeLease,AmaneHash} from "../../../src/AmaneTypes.sol";
contract FullAuthorityHandler is Test {
 using AmaneHash for *;
 ArcAuthority public account;ActionIntent private template;ActionIntent private last;bytes private lastSig;
 uint256 immutable agentKey;uint256 immutable controllerKey;uint256 public nextNonce=1;uint256 public total;uint256 public escapes;uint256 public replays;uint256 public controls;
 mapping(uint256=>uint256) public periodSpend;
 constructor(ArcAuthority a,ActionIntent memory t,uint256 agent_,uint256 controller_){account=a;template=t;agentKey=agent_;controllerKey=controller_;}
 function sign(uint256 key,bytes32 h) internal pure returns(bytes memory){(uint8 v,bytes32 r,bytes32 s)=vm.sign(key,h);return abi.encodePacked(r,s,v);}
 function actionHash(ActionIntent calldata a) external view returns(bytes32){return account.signingDigest(a.hash());}
 function spend(uint256 amount,bool redirect) external {
  ActionIntent memory a=template;a.nonce=uint64(nextNonce++);a.amountIn=bound(amount,1,30_000000);a.deadline=uint64(block.timestamp+60);if(redirect)a.recipient=bytes32(uint256(0xbad));bytes memory sig=sign(agentKey,this.actionHash(a));
  AmaneStorage.Lease memory l=account.lease(a.leaseId);bool forbidden=redirect||account.paused()||l.status!=1||block.timestamp<l.validAfter||block.timestamp>l.expiresAt;
  try account.executeAction(a,sig){if(forbidden)escapes++;total+=a.amountIn;periodSpend[block.timestamp/3600]+=a.amountIn;last=a;lastSig=sig;}catch{}
 }
 function replay() external {if(lastSig.length==0)return;try account.executeAction(last,lastSig){replays++;}catch{}}
 function pause() external {PauseAccount memory p=PauseAccount(template.accountId,account.pauseEpoch(),bytes32(++controls),uint64(block.timestamp+60));account.pause(p,sign(controllerKey,account.signingDigest(keccak256(abi.encode(keccak256("PauseAccount(bytes32 accountId,uint64 pauseEpoch,bytes32 pauseId,uint64 deadline)"),p)))));}
 function revoke() external {RevokeLease memory r=RevokeLease(template.accountId,template.leaseId);account.revokeLease(r,sign(controllerKey,account.signingDigest(keccak256(abi.encode(keccak256("RevokeLease(bytes32 accountId,bytes32 leaseId)"),r)))));}
 function advance(uint256 seconds_) external {vm.warp(block.timestamp+bound(seconds_,0,4000));}
}
contract FullAuthorityInvariants is AuthorityBase {
 FullAuthorityHandler handler;
 function setUp() public override {super.setUp();_install(_policy(1));_activate(_lease(issuer),pkIssuer);handler=new FullAuthorityHandler(acct,_pay(1,1),pkAgent,pkA);targetContract(address(handler));}
 function invariant_agent_root_and_issuer_caps_hold() public view {assertLe(handler.total(),100_000000);(,AmaneStorage.Spend memory s)=acct.rootBudget(a32(address(usd)));assertEq(s.totalSpent,handler.total());assertLe(handler.periodSpend(block.timestamp/3600),50_000000);}
 function invariant_no_replay_or_redirect_pause_revoke_escape() public view {assertEq(handler.escapes(),0);assertEq(handler.replays(),0);assertEq(usd.balanceOf(address(0xbad)),0);}
 function invariant_exact_token_conservation() public view {assertEq(usd.balanceOf(address(acct))+usd.balanceOf(merchant),1000_000000);assertEq(usd.balanceOf(merchant),handler.total());}
}
