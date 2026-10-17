// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
interface IQuotaMessageTransmitter {function sendMessage(uint32 destinationDomain,bytes32 recipient,bytes32 destinationCaller,uint32 minFinalityThreshold,bytes calldata messageBody) external;}
/// CCTP finalized-message boundary. Provider attesters/upgrades are trusted; no backend JSON is accepted.
abstract contract QuotaSync {
 address public immutable transmitter;bytes32 public immutable transmitterCodeHash;
 constructor(address transmitter_){require(transmitter_.code.length>0,"NO_TRANSMITTER");transmitter=transmitter_;transmitterCodeHash=transmitter_.codehash;}
 function _send(uint32 domain,address recipient,bytes memory body) internal {require(transmitter.codehash==transmitterCodeHash,"TRANSMITTER_CHANGED");IQuotaMessageTransmitter(transmitter).sendMessage(domain,bytes32(uint256(uint160(recipient))),bytes32(0),2000,body);}
 function _authenticate(uint32 finality) internal view {require(msg.sender==transmitter&&transmitter.codehash==transmitterCodeHash&&finality>=2000,"UNAUTHENTICATED_SYNC");}
 function handleReceiveUnfinalizedMessage(uint32,bytes32,uint32,bytes calldata) external pure returns(bool){revert("FINALIZED_ONLY");}
}
library QuotaTypes {
 struct Grant {bytes32 policyHash;bytes32 asset;bytes32 endpointChain;address endpoint;uint64 epoch;uint64 nonce;uint64 expiresAt;uint256 amount;}
 function id(Grant memory g) internal pure returns(bytes32){return keccak256(abi.encode(keccak256("AMANE_GLOBAL_QUOTA_V3"),g));}
}
