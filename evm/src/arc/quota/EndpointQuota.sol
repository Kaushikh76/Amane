// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {QuotaSync,QuotaTypes} from "./QuotaSync.sol";
contract EndpointQuota is QuotaSync {
 using QuotaTypes for QuotaTypes.Grant;
 struct Balance {uint256 issued;uint256 spent;uint64 expiresAt;bool installed;bool frozen;}
 address public immutable root;uint32 public immutable rootDomain;address public immutable endpoint;bytes32 public immutable endpointChain;bytes32 public immutable policyHash;bytes32 public immutable asset;
 mapping(bytes32=>Balance) public balances;
 event Consumed(bytes32 indexed id,uint256 amount);event Frozen(bytes32 indexed id,uint256 spent);
 constructor(address transmitter_,address root_,uint32 rootDomain_,address endpoint_,bytes32 chain_,bytes32 policy_,bytes32 asset_) QuotaSync(transmitter_){require(root_!=address(0)&&endpoint_!=address(0)&&chain_!=0&&policy_!=0&&asset_!=0,"BAD_ENDPOINT");root=root_;rootDomain=rootDomain_;endpoint=endpoint_;endpointChain=chain_;policyHash=policy_;asset=asset_;}
 function handleReceiveFinalizedMessage(uint32 domain,bytes32 sender,uint32 finality,bytes calldata body) external returns(bool){
  _authenticate(finality);require(domain==rootDomain&&sender==bytes32(uint256(uint160(root))),"WRONG_ROOT");
  (uint8 kind,bytes32 id)=abi.decode(body,(uint8,bytes32));Balance storage b=balances[id];
  if(kind==1){(,,QuotaTypes.Grant memory g)=abi.decode(body,(uint8,bytes32,QuotaTypes.Grant));require(g.id()==id&&g.policyHash==policyHash&&g.asset==asset&&g.endpointChain==endpointChain&&g.endpoint==endpoint&&!b.installed&&!b.frozen,"WRONG_GRANT");b.issued=g.amount;b.expiresAt=g.expiresAt;b.installed=true;}
  else if(kind==2){b.frozen=true;_send(rootDomain,root,abi.encode(uint8(3),id,b.spent));emit Frozen(id,b.spent);}
  else revert("UNKNOWN_MESSAGE");return true;
 }
 function consume(bytes32 id,uint256 amount) external {Balance storage b=balances[id];require(msg.sender==endpoint&&b.installed&&!b.frozen&&block.timestamp<=b.expiresAt&&amount>0&&b.spent+amount<=b.issued,"QUOTA_EXCEEDED");b.spent+=amount;emit Consumed(id,amount);}
 function resendAcknowledgement(bytes32 id) external {Balance memory b=balances[id];require(b.frozen,"NOT_FROZEN");_send(rootDomain,root,abi.encode(uint8(3),id,b.spent));}
}
