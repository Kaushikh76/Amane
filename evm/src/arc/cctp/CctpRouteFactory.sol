// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {CctpReceivingVault} from "./CctpReceivingVault.sol";
import {CctpDestinationAdapter} from "./CctpDestinationAdapter.sol";
contract CctpRouteFactory {
 struct Route {address account;address token;address transmitter;bytes32 sourceMessenger;bytes32 destinationMessenger;bytes32 sourceToken;address sourceAccount;address sourceAdapter;uint256 maximumFee;uint256 minimumArrival;bytes32 destinationSpecHash;}
 event RouteCreated(address indexed vault,address indexed adapter,address indexed account,bytes32 indexedSpec);
 function _args(Route calldata r) private pure returns(bytes memory){return abi.encode(r.account,r.token,r.transmitter,r.sourceMessenger,r.destinationMessenger,r.sourceToken,r.sourceAccount,r.sourceAdapter,r.maximumFee,r.minimumArrival,r.destinationSpecHash);}
 function _salt(Route calldata r,bytes32 userSalt) private pure returns(bytes32){return keccak256(abi.encode(r,userSalt));}
 function predict(Route calldata r,bytes32 userSalt) public view returns(address){bytes32 hash=keccak256(abi.encodePacked(type(CctpReceivingVault).creationCode,_args(r)));return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),_salt(r,userSalt),hash)))));}
 function create(Route calldata r,bytes32 userSalt) external returns(CctpReceivingVault vault,CctpDestinationAdapter adapter){
  address expected=predict(r,userSalt);if(expected.code.length>0){vault=CctpReceivingVault(expected);return(vault,CctpDestinationAdapter(vault.adapter()));}
  vault=new CctpReceivingVault{salt:_salt(r,userSalt)}(r.account,r.token,r.transmitter,r.sourceMessenger,r.destinationMessenger,r.sourceToken,r.sourceAccount,r.sourceAdapter,r.maximumFee,r.minimumArrival,r.destinationSpecHash);
  adapter=new CctpDestinationAdapter(vault);vault.bind(address(adapter));emit RouteCreated(address(vault),address(adapter),r.account,r.destinationSpecHash);
 }
}
