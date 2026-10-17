// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {IAmaneAdapter} from "../../AdapterRegistry.sol";
interface ICctpTokenMessenger {function depositForBurnWithHook(uint256 amount,uint32 destinationDomain,bytes32 mintRecipient,address burnToken,bytes32 destinationCaller,uint256 maxFee,uint32 minFinalityThreshold,bytes calldata hookData) external;}
interface ICctpErc20 {function balanceOf(address) external view returns(uint256);function transfer(address,uint256) external returns(bool);function approve(address,uint256) external returns(bool);}
/// Immutable route. Only the named authority can burn; hook binds its verified action digest.
contract CctpSourceAdapter is IAmaneAdapter {
 bytes32 public constant HOOK_TAG=keccak256("AMANE_CCTP_AUTHORITY_V3_HOOK");
 address public immutable sourceAccount;address public immutable token;address public immutable messenger;bytes32 public immutable messengerCodeHash;
 address public immutable destinationAccount;address public immutable vault;uint256 public immutable maxFee;uint256 public immutable minimumArrival;bytes32 public immutable destinationSpecHash;
 constructor(address account_,address token_,address messenger_,address destinationAccount_,address vault_,uint256 maxFee_,uint256 minimumArrival_,bytes32 destinationSpecHash_){
  require(block.chainid==11155111||block.chainid==31337,"SOURCE_CHAIN");require(account_!=address(0)&&token_.code.length>0&&messenger_.code.length>0&&destinationAccount_!=address(0)&&vault_!=address(0),"BAD_ROUTE");
  sourceAccount=account_;token=token_;messenger=messenger_;messengerCodeHash=messenger_.codehash;destinationAccount=destinationAccount_;vault=vault_;maxFee=maxFee_;require(minimumArrival_>0,"MINIMUM");minimumArrival=minimumArrival_;require(destinationSpecHash_!=0,"DESTINATION_SPEC");destinationSpecHash=destinationSpecHash_;
 }
 function actionKind() external pure returns(uint8){return 10;}
 function adapterName() external pure returns(string memory){return "Amane CCTP V2 Source";}
 function adapterVersion() external pure returns(uint32){return 3;}
 function execute(address,address,uint256,uint256,address) external pure {revert("USE_BRIDGE");}
 /// Dust always returns to the account; no caller can select a payout address.
 function sweepDonation() external {uint256 balance=ICctpErc20(token).balanceOf(address(this));if(balance>0)require(ICctpErc20(token).transfer(sourceAccount,balance),"RETURN_DONATION");}
 function bridge(address tokenIn,uint256 amount,bytes32 recipient,bytes32 intent) external {
  require(msg.sender==sourceAccount&&tokenIn==token&&recipient==bytes32(uint256(uint160(destinationAccount)))&&amount>maxFee&&amount-maxFee>=minimumArrival&&intent!=0,"BAD_BURN");
  require(messenger.codehash==messengerCodeHash,"MESSENGER_CHANGED");require(ICctpErc20(token).balanceOf(address(this))==amount,"EXACT_INPUT");
  require(ICctpErc20(token).approve(messenger,amount),"APPROVE");
  ICctpTokenMessenger(messenger).depositForBurnWithHook(amount,26,bytes32(uint256(uint160(vault))),token,bytes32(uint256(uint160(vault))),maxFee,2000,abi.encode(HOOK_TAG,sourceAccount,destinationAccount,intent,destinationSpecHash));
  require(ICctpErc20(token).balanceOf(address(this))==0,"BURN_NOT_EXACT");require(ICctpErc20(token).approve(messenger,0),"CLEAR_APPROVAL");
 }
}
