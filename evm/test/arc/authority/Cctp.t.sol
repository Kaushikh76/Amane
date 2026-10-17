// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {AmaneTestToken} from "../../../src/AmaneTestToken.sol";
import {CctpSourceAdapter} from "../../../src/arc/cctp/CctpSourceAdapter.sol";
import {CctpReceivingVault} from "../../../src/arc/cctp/CctpReceivingVault.sol";
import {CctpDestinationAdapter} from "../../../src/arc/cctp/CctpDestinationAdapter.sol";
import {CctpMessage} from "../../../src/arc/cctp/CctpMessage.sol";
import {AdapterRegistry} from "../../../src/AdapterRegistry.sol";
/// Local issuer fixture, never a claimed Circle attestation or live provider deployment.
contract CctpTransmitterFixture {
 AmaneTestToken immutable token;address immutable attester;mapping(bytes32=>bool) used;
 constructor(AmaneTestToken t,address a){token=t;attester=a;}
 function receiveMessage(bytes calldata m,bytes calldata a) external returns(bool){
  CctpMessage.Burn memory b=CctpMessage.parse(m);require(b.destinationCaller==bytes32(uint256(uint160(msg.sender))),"CALLER");
  require(a.length==65,"BAD_ATTESTATION");bytes32 r;bytes32 s;uint8 v;assembly("memory-safe"){r:=calldataload(a.offset) s:=calldataload(add(a.offset,32)) v:=byte(0,calldataload(add(a.offset,64)))}
  require(ecrecover(keccak256(m),v,r,s)==attester&&!used[b.nonce],"BAD_ATTESTATION");used[b.nonce]=true;token.mint(msg.sender,b.amount-b.fee);return true;
 }
}
contract CctpMessengerFixture {
 bytes public hook;uint256 public amount;bytes32 public vault;
 function depositForBurnWithHook(uint256 a,uint32 d,bytes32 recipient,address token,bytes32 caller,uint256,uint32 finality,bytes calldata h) external {
  require(d==26&&caller==recipient&&finality==2000,"WRONG_ROUTE");AmaneTestToken(token).transferFrom(msg.sender,address(this),a);hook=h;amount=a;vault=recipient;
 }
}
contract CctpAuthorityTest is Test {
 AmaneTestToken token;CctpTransmitterFixture transmitter;CctpMessengerFixture messenger;CctpReceivingVault vault;CctpDestinationAdapter destination;CctpSourceAdapter source;
 address account=address(0x123);address sourceAccount=address(0x456);uint256 constant ATTESTER_PK=34341;bytes32 constant SPEC=keccak256("fixture-destination-spec");
 bytes32 constant INTENT=keccak256("test-only-intent");
 function a32(address a) internal pure returns(bytes32){return bytes32(uint256(uint160(a)));}
 function setUp() public {
  vm.chainId(31337);token=new AmaneTestToken("Fixture USD","USDC",6);transmitter=new CctpTransmitterFixture(token,vm.addr(ATTESTER_PK));messenger=new CctpMessengerFixture();
  address expectedSource=vm.computeCreateAddress(address(this),vm.getNonce(address(this))+1);
  vault=new CctpReceivingVault(account,address(token),address(transmitter),a32(address(messenger)),a32(address(0x789)),a32(address(token)),sourceAccount,expectedSource,10,90,SPEC);
  source=new CctpSourceAdapter(sourceAccount,address(token),address(messenger),account,address(vault),10,90,SPEC);assertEq(address(source),expectedSource);
  destination=new CctpDestinationAdapter(vault);vault.bind(address(destination));
 }
 function _message(bytes32 intent,uint256 fee) internal view returns(bytes memory){
  return abi.encodePacked(uint32(1),uint32(0),uint32(26),bytes32(uint256(1)),a32(address(messenger)),a32(address(0x789)),a32(address(vault)),uint32(2000),uint32(2000),uint32(1),a32(address(token)),a32(address(vault)),uint256(100),a32(address(source)),uint256(10),fee,uint256(0),abi.encode(keccak256("AMANE_CCTP_AUTHORITY_V3_HOOK"),sourceAccount,account,intent,SPEC));
 }
 function _sig(bytes memory m) internal pure returns(bytes memory){(uint8 v,bytes32 r,bytes32 s)=vm.sign(ATTESTER_PK,keccak256(m));return abi.encodePacked(r,s,v);}
 function _redeem(bytes memory m,bytes memory a) internal returns(bytes32){vm.prank(account);return destination.redeem(abi.encode(m,a));}
 function test_authenticated_message_exact_mint_and_replay() public {bytes memory m=_message(INTENT,3);assertEq(_redeem(m,_sig(m)),INTENT);assertEq(token.balanceOf(account),97);vm.expectRevert();this.redeemExternal(m,_sig(m));assertEq(token.balanceOf(account),97);}
 function redeemExternal(bytes memory m,bytes memory a) external returns(bytes32){return _redeem(m,a);}
 function test_forged_attestation_and_modified_hook_rejected() public {bytes memory m=_message(INTENT,3);bytes memory sig=_sig(m);m[m.length-1]=bytes1(uint8(m[m.length-1])^1);vm.expectRevert();this.redeemExternal(m,sig);assertEq(token.balanceOf(account),0);}
 function test_fee_over_cap_and_wrong_origin_rejected() public {bytes memory m=_message(INTENT,11);vm.expectRevert();this.redeemExternal(m,_sig(m));m=_message(INTENT,3);m[251]=bytes1(uint8(1));vm.expectRevert();this.redeemExternal(m,_sig(m));assertEq(token.balanceOf(account),0);}
 function test_donation_does_not_count_as_mint() public {token.mint(address(vault),200);bytes memory m=_message(INTENT,3);_redeem(m,_sig(m));assertEq(token.balanceOf(account),97);assertEq(token.balanceOf(address(vault)),200);vault.sweepDonation();assertEq(token.balanceOf(address(vault)),0);assertEq(token.balanceOf(account),297);}
 function test_source_binds_account_vault_hook_and_fee() public {token.mint(address(source),100);vm.prank(sourceAccount);source.bridge(address(token),100,a32(account),INTENT);assertEq(messenger.amount(),100);assertEq(messenger.vault(),a32(address(vault)));assertEq(keccak256(messenger.hook()),keccak256(abi.encode(keccak256("AMANE_CCTP_AUTHORITY_V3_HOOK"),sourceAccount,account,INTENT,SPEC)));}
 function test_source_shortfall_rejected_before_burn() public {token.mint(address(source),11);vm.prank(sourceAccount);vm.expectRevert("BAD_BURN");source.bridge(address(token),11,a32(account),INTENT);assertEq(token.balanceOf(address(source)),11);}
 function test_donation_returns_only_to_pinned_source_account() public {token.mint(address(source),1);source.sweepDonation();assertEq(token.balanceOf(sourceAccount),1);assertEq(token.balanceOf(address(source)),0);}
 function test_source_cannot_be_used_by_other_sender() public {token.mint(address(source),100);vm.expectRevert();source.bridge(address(token),100,a32(account),INTENT);assertEq(token.balanceOf(address(source)),100);}
 function test_destination_and_source_adapters_register_immutable_code() public {AdapterRegistry registry=new AdapterRegistry();assertNotEq(registry.register(address(source)),bytes32(0));assertNotEq(registry.register(address(destination)),bytes32(0));}
 function test_vault_cannot_be_rebound_or_redeemed_directly() public {vm.expectRevert();vault.bind(address(source));bytes memory m=_message(INTENT,3);vm.expectRevert();vault.receiveAndRelease(m,_sig(m));}
}
