// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {CctpMessage} from "./CctpMessage.sol";
import {ICctpErc20} from "./CctpSourceAdapter.sol";
interface ICctpMessageTransmitter {function receiveMessage(bytes calldata message,bytes calldata attestation) external returns(bool);}
/// Custody authenticates the raw message in the same transaction that measures and releases its mint.
/// The provider's attesters and upgrade governance remain explicit trusted upstream dependencies.
contract CctpReceivingVault {
 bytes32 public constant HOOK_TAG=keccak256("AMANE_CCTP_AUTHORITY_V3_HOOK");
 address public immutable account;address public immutable token;address public immutable transmitter;bytes32 public immutable transmitterCodeHash;
 bytes32 public immutable sourceMessenger;bytes32 public immutable destinationMessenger;bytes32 public immutable sourceToken;address public immutable sourceAccount;address public immutable sourceAdapter;
 address public immutable factory;address public adapter;uint256 public immutable maximumFee;uint256 public immutable minimumArrival;bytes32 public immutable destinationSpecHash;
 bool private locked;mapping(bytes32=>bool) public consumed;
 event AuthenticatedMint(bytes32 indexed nonce,bytes32 indexed intent,uint256 amount,uint256 fee);
 constructor(address account_,address token_,address transmitter_,bytes32 sourceMessenger_,bytes32 destinationMessenger_,bytes32 sourceToken_,address sourceAccount_,address sourceAdapter_,uint256 maximumFee_,uint256 minimumArrival_,bytes32 destinationSpecHash_){
  require(block.chainid==5042002||block.chainid==31337,"DESTINATION_CHAIN");require(account_!=address(0)&&token_.code.length>0&&transmitter_.code.length>0&&sourceAccount_!=address(0)&&sourceAdapter_!=address(0)&&minimumArrival_>0,"BAD_ROUTE");
  account=account_;token=token_;transmitter=transmitter_;transmitterCodeHash=transmitter_.codehash;sourceMessenger=sourceMessenger_;destinationMessenger=destinationMessenger_;sourceToken=sourceToken_;sourceAccount=sourceAccount_;sourceAdapter=sourceAdapter_;maximumFee=maximumFee_;minimumArrival=minimumArrival_;require(destinationSpecHash_!=0,"DESTINATION_SPEC");destinationSpecHash=destinationSpecHash_;factory=msg.sender;
 }
 function bind(address adapter_) external {require(msg.sender==factory&&adapter==address(0)&&adapter_.code.length>0,"BIND_ONCE");adapter=adapter_;}
 /// Unsolicited token donations are returned only to the bounded account, never credited as mint.
 function sweepDonation() external {require(!locked,"MINT_IN_PROGRESS");uint256 balance=ICctpErc20(token).balanceOf(address(this));if(balance>0)require(ICctpErc20(token).transfer(account,balance),"RETURN_DONATION");}
 function receiveAndRelease(bytes calldata message,bytes calldata attestation) external returns(bytes32 intent){
  require(msg.sender==adapter&&!locked,"ONLY_TRANSPORT");locked=true;
  require(transmitter.codehash==transmitterCodeHash,"TRANSMITTER_CHANGED");CctpMessage.Burn memory b=CctpMessage.parse(message);
  require(b.sourceDomain==0&&b.destinationDomain==26&&b.sender==sourceMessenger&&b.recipient==destinationMessenger,"WRONG_ROUTE");
  require(b.destinationCaller==bytes32(uint256(uint160(address(this))))&&b.mintRecipient==bytes32(uint256(uint160(address(this))))&&b.burnToken==sourceToken&&b.messageSender==bytes32(uint256(uint160(sourceAdapter))),"WRONG_ORIGIN");
  require(b.maxFee<=maximumFee&&b.amount-b.fee>=minimumArrival&&!consumed[b.nonce]&&b.hook.length==160,"FEE_OR_REPLAY");
  (bytes32 tag,address source,address destination,bytes32 carried,bytes32 spec)=abi.decode(b.hook,(bytes32,address,address,bytes32,bytes32));
  require(tag==HOOK_TAG&&source==sourceAccount&&destination==account&&carried!=0&&spec==destinationSpecHash,"WRONG_INTENT");intent=carried;consumed[b.nonce]=true;
  uint256 beforeBalance=ICctpErc20(token).balanceOf(address(this));
  require(ICctpMessageTransmitter(transmitter).receiveMessage(message,attestation),"ATTESTATION_FAILED");
  uint256 minted=ICctpErc20(token).balanceOf(address(this))-beforeBalance;require(minted==b.amount-b.fee,"MINT_NOT_EXACT");
  uint256 beforeAccount=ICctpErc20(token).balanceOf(account);require(ICctpErc20(token).transfer(account,minted),"TRANSFER");
  require(ICctpErc20(token).balanceOf(address(this))==beforeBalance&&ICctpErc20(token).balanceOf(account)-beforeAccount==minted,"RELEASE_NOT_EXACT");
  locked=false;emit AuthenticatedMint(b.nonce,intent,minted,b.fee);
 }
}
