// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {IAmaneAdapter} from "../../AdapterRegistry.sol";
import {CctpReceivingVault} from "./CctpReceivingVault.sol";
/// Immutable stateless transport: only the pinned destination authority can redeem into its custody.
contract CctpDestinationAdapter is IAmaneAdapter {
 CctpReceivingVault public immutable vault;address public immutable account;bytes32 public immutable vaultCodeHash;
 constructor(CctpReceivingVault vault_){vault=vault_;account=vault_.account();vaultCodeHash=address(vault_).codehash;}
 function actionKind() external pure returns(uint8){return 10;}
 function adapterName() external pure returns(string memory){return "Amane CCTP V2 Destination";}
 function adapterVersion() external pure returns(uint32){return 3;}
 function execute(address,address,uint256,uint256,address) external pure {revert("USE_REDEEM");}
 function redeem(bytes calldata data) external returns(bytes32 intent){require(msg.sender==account&&address(vault).codehash==vaultCodeHash,"ONLY_AUTHORITY");(bytes memory message,bytes memory attestation)=abi.decode(data,(bytes,bytes));return vault.receiveAndRelease(message,attestation);}
}
