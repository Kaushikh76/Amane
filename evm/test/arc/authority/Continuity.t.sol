// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AuthorityBase} from "./AuthorityBase.sol";
import {ArcAuthority} from "../../../src/arc/authority/ArcAuthority.sol";
import {CctpSourceAdapter} from "../../../src/arc/cctp/CctpSourceAdapter.sol";
import {CctpReceivingVault} from "../../../src/arc/cctp/CctpReceivingVault.sol";
import {CctpDestinationAdapter} from "../../../src/arc/cctp/CctpDestinationAdapter.sol";
import {CctpTransmitterFixture,CctpMessengerFixture} from "./Cctp.t.sol";
import "../../../src/AmaneTypes.sol";
import {Codes} from "../../../src/AmaneCodes.sol";
/// Local transport fixture end-to-end. Attester key is test-only; this is not Circle proof.
contract AuthorityContinuityTest is AuthorityBase {
 ArcAuthority destinationAccount;CctpReceivingVault vault;CctpSourceAdapter sourceAdapter;CctpDestinationAdapter transport;CctpMessengerFixture messenger;CctpTransmitterFixture transmitter;
 bytes32 sourceId;bytes32 transportId;DestSpec destination;uint256 constant ATTESTER=34341;
 function specHash(DestSpec calldata d) external pure returns(bytes32){return DestSpecHash.hash(d);}
 function setUp() public override {
  super.setUp();destinationAccount=ArcAuthority(deployCode("ArcAuthority.sol:ArcAuthority",abi.encode(ACCOUNT_ID,_sorted(ctrlA,ctrlB),2,registry,acct.ext())));messenger=CctpMessengerFixture(deployCode("Cctp.t.sol:CctpMessengerFixture"));transmitter=CctpTransmitterFixture(deployCode("Cctp.t.sol:CctpTransmitterFixture",abi.encode(usd,vm.addr(ATTESTER))));destination=DestSpec(9,payId,a32(merchant),unicode"Merchant ✓ café",a32(address(usd)),90,uint64(T0+1800));bytes32 spec=this.specHash(destination);
  address expectedSource=vm.computeCreateAddress(address(this),vm.getNonce(address(this))+1);
  vault=CctpReceivingVault(deployCode("CctpReceivingVault.sol:CctpReceivingVault",abi.encode(address(destinationAccount),address(usd),address(transmitter),a32(address(messenger)),a32(address(0x789)),a32(address(usd)),address(acct),expectedSource,10,90,spec)));
  sourceAdapter=CctpSourceAdapter(deployCode("CctpSourceAdapter.sol:CctpSourceAdapter",abi.encode(address(acct),address(usd),address(messenger),address(destinationAccount),address(vault),10,90,spec)));transport=CctpDestinationAdapter(deployCode("CctpDestinationAdapter.sol:CctpDestinationAdapter",abi.encode(vault)));vault.bind(address(transport));sourceId=registry.register(address(sourceAdapter));transportId=registry.register(address(transport));
  RootPolicy memory p=_policy(1);p.allowedActions=(1<<9)|(1<<10);p.endpoints[0].adapters=new AdapterRef[](3);p.endpoints[0].adapters[0]=AdapterRef(payId,"Transfer Pay",1);p.endpoints[0].adapters[1]=AdapterRef(sourceId,"Amane CCTP V2 Source",3);p.endpoints[0].adapters[2]=AdapterRef(transportId,"Amane CCTP V2 Destination",3);p.endpoints[0].recipients=new Recipient[](2);p.endpoints[0].recipients[0]=Recipient(a32(merchant),unicode"Merchant ✓ café");p.endpoints[0].recipients[1]=Recipient(a32(address(destinationAccount)),"Endpoint");p.endpoints[1]=abi.decode(abi.encode(p.endpoints[0]),(PolicyEndpoint));p.endpoints[1].account=a32(address(destinationAccount));
  _install(p);ArcAuthority source=acct;acct=destinationAccount;_install(p);acct=source;
  AgentLease memory l=_lease(ctrlA);l.allowedActions=p.allowedActions;l.endpoints[0].adapters=new bytes32[](3);l.endpoints[0].adapters[0]=payId;l.endpoints[0].adapters[1]=sourceId;l.endpoints[0].adapters[2]=transportId;l.endpoints[0].recipients=new bytes32[](2);l.endpoints[0].recipients[0]=a32(merchant);l.endpoints[0].recipients[1]=a32(address(destinationAccount));l.endpoints[1]=abi.decode(abi.encode(l.endpoints[0]),(LeaseEndpoint));l.endpoints[1].account=a32(address(destinationAccount));_activate(l,pkA);acct=destinationAccount;_activate(l,pkA);acct=source;
 }
 function _source() internal view returns(ActionIntent memory a){a=_pay(1,100);a.actionKind=10;a.adapterId=sourceId;a.adapterName="Amane CCTP V2 Source";a.adapterVersion=3;a.recipient=a32(address(destinationAccount));a.recipientLabel="Endpoint";a.planHash=this.specHash(destination);}
 function _message(bytes32 digest) internal view returns(bytes memory){return abi.encodePacked(uint32(1),uint32(0),uint32(26),bytes32(uint256(1)),a32(address(messenger)),a32(address(0x789)),a32(address(vault)),uint32(2000),uint32(2000),uint32(1),a32(address(usd)),a32(address(vault)),uint256(100),a32(address(sourceAdapter)),uint256(10),uint256(3),uint256(0),abi.encode(keccak256("AMANE_CCTP_AUTHORITY_V3_HOOK"),address(acct),address(destinationAccount),digest,this.specHash(destination)));}
 function _attest(bytes memory m) internal pure returns(bytes memory){(uint8 v,bytes32 r,bytes32 s)=vm.sign(ATTESTER,keccak256(m));return abi.encodePacked(r,s,v);}
 function test_source_policy_burn_authenticates_reserves_and_executes_destination() public {
  ActionIntent memory src=_source();bytes memory srcSig=_agentSig(src);bytes32 intent=this.hAction(src);_exec(src);assertEq(messenger.amount(),100);bytes memory m=_message(intent);destinationAccount.receiveCrossChain(src,srcSig,destination,transportId,abi.encode(m,_attest(m)));assertEq(destinationAccount.reservedOf(address(usd)),97);
  ArcAuthority source=acct;acct=destinationAccount;ActionIntent memory pay=_pay(2,97);pay.planHash=intent;bytes memory sig=_agentSig(pay);acct.executeReserved(intent,pay,sig);acct=source;assertEq(usd.balanceOf(merchant),97);assertEq(destinationAccount.reservedOf(address(usd)),0);
 }
 function test_delayed_mint_after_revoke_enters_quarantine_then_root_recovery() public {
  ActionIntent memory src=_source();bytes memory srcSig=_agentSig(src);bytes32 intent=this.hAction(src);_exec(src);bytes memory m=_message(intent);ArcAuthority source=acct;acct=destinationAccount;RevokeLease memory r=RevokeLease(ACCOUNT_ID,leaseId);acct.revokeLease(r,_sign(pkA,this.hRevoke(r)));acct=source;
  destinationAccount.recoverArrival(src,srcSig,destination,transportId,abi.encode(m,_attest(m)));assertEq(destinationAccount.quarantinedOf(address(usd)),97);assertEq(usd.balanceOf(merchant),0);
  acct=destinationAccount;Withdraw memory w=Withdraw(ACCOUNT_ID,acct.chainRef(),a32(address(acct)),a32(address(usd)),97,a32(recovery),0,uint64(T0+100));acct.withdraw(w,_both(this.hWithdraw(w)));acct=source;assertEq(usd.balanceOf(recovery),97);assertEq(destinationAccount.quarantinedOf(address(usd)),0);
 }
 function test_source_spec_mutation_and_merchant_bridge_reject_before_burn() public {ActionIntent memory src=_source();src.planHash=keccak256("different spec");bytes memory sig=_agentSig(src);vm.expectRevert("BRIDGE_SPEC_MISMATCH");acct.executeAction(src,sig);assertFalse(acct.nonceUsed(leaseId,1));src=_source();src.recipient=a32(merchant);src.recipientLabel=unicode"Merchant ✓ café";_execReject(src,Codes.XCHAIN_WRONG_DESTINATION);assertEq(messenger.amount(),0);}
}
