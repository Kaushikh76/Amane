// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
/// Independently implemented parser for Circle CCTP V2 documented packed message format.
/// https://developers.circle.com/cctp/references/technical-guide (2026-10-17)
library CctpMessage {
 struct Burn {uint32 sourceDomain;uint32 destinationDomain;bytes32 nonce;bytes32 sender;bytes32 recipient;bytes32 destinationCaller;uint32 finality;bytes32 burnToken;bytes32 mintRecipient;uint256 amount;bytes32 messageSender;uint256 maxFee;uint256 fee;bytes hook;}
 error InvalidMessage();
 function word(bytes calldata data,uint256 offset) internal pure returns(bytes32 out){if(data.length<offset+32)revert InvalidMessage();assembly("memory-safe"){out:=calldataload(add(data.offset,offset))}}
 function u32(bytes calldata data,uint256 offset) internal pure returns(uint32 out){if(data.length<offset+4)revert InvalidMessage();assembly("memory-safe"){out:=shr(224,calldataload(add(data.offset,offset)))}}
 function parse(bytes calldata data) internal pure returns(Burn memory b){
  if(data.length<376 || u32(data,0)!=1 || u32(data,148)!=1)revert InvalidMessage();
  b.sourceDomain=u32(data,4);b.destinationDomain=u32(data,8);b.nonce=word(data,12);b.sender=word(data,44);b.recipient=word(data,76);b.destinationCaller=word(data,108);b.finality=u32(data,144);
  b.burnToken=word(data,152);b.mintRecipient=word(data,184);b.amount=uint256(word(data,216));b.messageSender=word(data,248);b.maxFee=uint256(word(data,280));b.fee=uint256(word(data,312));b.hook=data[376:];
  if(b.amount==0 || b.fee>b.maxFee || b.fee>=b.amount || b.finality<2000)revert InvalidMessage();
 }
}
