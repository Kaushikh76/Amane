// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import "../../../src/AmaneTypes.sol";
import {IAmaneAdapter} from "../../../src/AdapterRegistry.sol";
import {AmaneTestToken} from "../../../src/AmaneTestToken.sol";
import {ArcAuthorityDomain as Domain} from "../../../src/arc/authority/ArcAuthorityDomain.sol";
import {Codes} from "../../../src/AmaneCodes.sol";
/// Local transport fixture proves accounting only; it does not authenticate any live bridge.
contract AuthorityFixtureTransport is IAmaneAdapter {
 function actionKind() external pure returns(uint8){return 10;}
 function adapterName() external pure returns(string memory){return "Authority Fixture Transport";}
 function adapterVersion() external pure returns(uint32){return 1;}
 function execute(address,address,uint256,uint256,address) external pure {revert();}
 function redeem(bytes calldata data) external returns(bytes32 digest){(address token,uint256 amount,bytes32 intent)=abi.decode(data,(address,uint256,bytes32));AmaneTestToken(token).mint(msg.sender,amount);return intent;}
}
contract AuthorityReservationTest is AuthorityBase {
 using AmaneHash for *;
 bytes32 transportId;
 bytes32 constant SOURCE_CHAIN=keccak256("eip155:11155111");
 address constant SOURCE_ACCOUNT=address(0x534);
 function setUp() public override {
  super.setUp();transportId=registry.register(address(new AuthorityFixtureTransport()));
  RootPolicy memory p=_policy(1);p.allowedActions|=1<<10;p.endpoints[1].chainRef=SOURCE_CHAIN;p.endpoints[1].account=a32(SOURCE_ACCOUNT);
  AdapterRef[] memory refs=new AdapterRef[](3);refs[0]=p.endpoints[0].adapters[0];refs[1]=p.endpoints[0].adapters[1];refs[2]=AdapterRef(transportId,"Authority Fixture Transport",1);p.endpoints[0].adapters=refs;_install(p);
  AgentLease memory l=_lease(ctrlA);l.allowedActions|=1<<10;bytes32[] memory ids=new bytes32[](3);ids[0]=payId;ids[1]=swapId;ids[2]=transportId;l.endpoints[0].adapters=ids;_activate(l,pkA);
 }
 function destHash(DestSpec calldata d) external pure returns(bytes32){return DestSpecHash.hash(d);}
 function sourceDigest(ActionIntent calldata a) external pure returns(bytes32){return Domain.source(a.hash(),a);}
 function _arrival(uint64 n) internal returns(bytes32 intent){
  DestSpec memory d=DestSpec(9,payId,a32(merchant),unicode"Merchant ✓ café",a32(address(usd)),1,type(uint64).max);
  ActionIntent memory src=_pay(n,100_000000);src.chainRef=SOURCE_CHAIN;src.account=a32(SOURCE_ACCOUNT);src.actionKind=10;src.recipient=a32(address(acct));src.planHash=this.destHash(d);
  intent=this.sourceDigest(src);acct.receiveCrossChain(src,_sign(pkAgent,intent),d,transportId,abi.encode(address(usd),100_000000,intent));
 }
 function _reserved(bytes32 intent,uint64 n,uint256 amount) internal {ActionIntent memory a=_pay(n,amount);a.planHash=intent;acct.executeReserved(intent,a,_agentSig(a));}
 function test_destination_caps_apply_to_reserved_execution() public {
  bytes32 intent=_arrival(1);ActionIntent memory a=_pay(1,26_000000);a.planHash=intent;bytes memory sig=_agentSig(a);_reject(Codes.BUDGET_PER_ACTION);acct.executeReserved(intent,a,sig);
  assertFalse(acct.nonceUsed(leaseId,1));_reserved(intent,1,25_000000);_reserved(intent,2,25_000000);
  a=_pay(3,1);a.planHash=intent;sig=_agentSig(a);_reject(Codes.BUDGET_EPOCH);acct.executeReserved(intent,a,sig);assertEq(usd.balanceOf(merchant),50_000000);
 }
 function test_revoked_reservation_quarantines_before_agent_deadline() public {bytes32 intent=_arrival(1);RevokeLease memory r=RevokeLease(ACCOUNT_ID,leaseId);acct.revokeLease(r,_sign(pkA,this.hRevoke(r)));acct.releaseReservation(intent);assertEq(acct.quarantinedOf(address(usd)),100_000000);(,,,,,,uint256 remaining)=acct.reservations(intent);assertEq(remaining,0);}
 function test_policy_rotation_quarantines_stale_reservation() public {bytes32 intent=_arrival(1);_install(_policy(2));acct.releaseReservation(intent);assertEq(acct.quarantinedOf(address(usd)),100_000000);}
 function test_pause_preserves_live_reservation() public {bytes32 intent=_arrival(1);PauseAccount memory p=_pauseMsg(keccak256("pause"));acct.pause(p,_sign(pkA,this.hPause(p)));_reject(Codes.XCHAIN_NO_RESERVATION);acct.releaseReservation(intent);assertEq(acct.quarantinedOf(address(usd)),0);}
 function deliverFixture(uint64 n) external returns(bytes32){return _arrival(n);}
 function test_duplicate_transport_delivery_cannot_credit_twice() public {bytes32 intent=_arrival(1);assertTrue(acct.intentUsed(intent));vm.expectRevert();this.deliverFixture(1);assertEq(acct.reservedOf(address(usd)),100_000000);}
}
