// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {IAmaneAdapter} from "../../AdapterRegistry.sol";
import {ICctpErc20} from "../cctp/CctpSourceAdapter.sol";
/// Versioned Amane escrow interface, not an assertion about an external provider's ABI.
interface IAmaneBoundedEscrow {
 function fund(bytes32 deal,address payer,uint256 amount) external;
 function funded(bytes32 deal,address payer) external view returns(uint256);
}
/// One account, token, deal and escrow target. Protocol credit AND custody increase are measured.
contract EscrowFundAdapter is IAmaneAdapter {
 address public immutable account;address public immutable token;address public immutable escrow;bytes32 public immutable escrowCodeHash;bytes32 public immutable deal;
 constructor(address account_,address token_,address escrow_,bytes32 deal_){require(account_!=address(0)&&token_.code.length>0&&escrow_.code.length>0&&deal_!=0,"BAD_ESCROW");account=account_;token=token_;escrow=escrow_;escrowCodeHash=escrow_.codehash;deal=deal_;}
 function actionKind() external pure returns(uint8){return 11;}
 function adapterName() external pure returns(string memory){return "Amane Escrow Fund";}
 function adapterVersion() external pure returns(uint32){return 3;}
 function sweepDonation() external {uint256 balance=ICctpErc20(token).balanceOf(address(this));if(balance>0)require(ICctpErc20(token).transfer(account,balance),"RETURN_DONATION");}
 function execute(address tokenIn,address tokenOut,uint256 amount,uint256 minimum,address recipient) external {
  require(msg.sender==account&&tokenIn==token&&tokenOut==token&&recipient==escrow&&amount>0&&minimum<=amount,"BAD_FUND");require(escrow.codehash==escrowCodeHash,"ESCROW_CHANGED");
  require(ICctpErc20(token).balanceOf(address(this))==amount,"EXACT_INPUT");uint256 beforeBalance=ICctpErc20(token).balanceOf(escrow);uint256 beforeCredit=IAmaneBoundedEscrow(escrow).funded(deal,account);
  require(ICctpErc20(token).approve(escrow,amount),"APPROVE");IAmaneBoundedEscrow(escrow).fund(deal,account,amount);require(ICctpErc20(token).approve(escrow,0),"CLEAR_APPROVAL");
  require(ICctpErc20(token).balanceOf(address(this))==0&&ICctpErc20(token).balanceOf(escrow)-beforeBalance==amount&&IAmaneBoundedEscrow(escrow).funded(deal,account)-beforeCredit==amount,"FUND_NOT_EXACT");
 }
}
