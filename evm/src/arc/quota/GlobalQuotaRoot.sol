// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {QuotaSync,QuotaTypes} from "./QuotaSync.sol";
import {AmaneSig} from "../../AmaneTypes.sol";
import {ArcAuthorityDomain as Domain} from "../authority/ArcAuthorityDomain.sol";
contract GlobalQuotaRoot is QuotaSync {
 using QuotaTypes for QuotaTypes.Grant;
 struct Allocation {address leaf;uint32 domain;uint64 epoch;uint256 amount;uint8 status;}
 bytes32 public immutable policyHash;bytes32 public immutable asset;uint256 public immutable totalLimit;uint256 public immutable periodLimit;uint64 public immutable periodSeconds;uint64 public immutable maxLifetime;
 uint8 public immutable threshold;mapping(address=>bool) public controller;uint64 public nonce;
 uint256 public outstanding;uint256 public finalizedSpent;mapping(uint64=>uint256) public epochEncumbered;mapping(bytes32=>Allocation) public allocations;
 event Allocated(bytes32 indexed id,address indexed leaf,uint256 amount);event FreezeRequested(bytes32 indexed id);event Reclaimed(bytes32 indexed id,uint256 spent,uint256 returned);
 constructor(address transmitter_,bytes32 policyHash_,bytes32 asset_,uint256 total_,uint256 period_,uint64 seconds_,uint64 lifetime_,address[] memory controllers,uint8 threshold_) QuotaSync(transmitter_){
  require(policyHash_!=0&&asset_!=0&&period_>0&&period_<=total_&&seconds_>0&&lifetime_>0&&threshold_>0&&threshold_<=controllers.length,"BAD_ROOT");
  policyHash=policyHash_;asset=asset_;totalLimit=total_;periodLimit=period_;periodSeconds=seconds_;maxLifetime=lifetime_;threshold=threshold_;
  address previous;for(uint256 i;i<controllers.length;i++){require(controllers[i]>previous,"SORTED_CONTROLLERS");controller[controllers[i]]=true;previous=controllers[i];}
 }
 function _threshold(bytes32 h,bytes[] calldata signatures) private view {require(signatures.length>=threshold,"THRESHOLD");address previous;bytes32 digest=Domain.at(h,block.chainid,address(this));for(uint256 i;i<signatures.length;i++){address signer=AmaneSig.recover(digest,signatures[i]);require(signer>previous&&controller[signer],"CONTROLLER");previous=signer;}}
 function allocationHash(QuotaTypes.Grant calldata g,address leaf,uint32 domain) public pure returns(bytes32){return keccak256(abi.encode(keccak256("AllocateQuota(bytes32 grantId,address leaf,uint32 domain)"),QuotaTypes.id(g),leaf,domain));}
 function allocate(QuotaTypes.Grant calldata g,address leaf,uint32 domain,bytes[] calldata signatures) external returns(bytes32 id){
  require(g.policyHash==policyHash&&g.asset==asset&&g.nonce==nonce&&g.endpoint!=address(0)&&leaf!=address(0)&&g.amount>0,"WRONG_GRANT");
  require(g.epoch==block.timestamp/periodSeconds&&g.expiresAt>block.timestamp&&g.expiresAt-block.timestamp<=maxLifetime&&g.expiresAt<(uint256(g.epoch)+1)*periodSeconds,"GRANT_WINDOW");
  require(finalizedSpent+outstanding+g.amount<=totalLimit&&epochEncumbered[g.epoch]+g.amount<=periodLimit,"GLOBAL_CAP");_threshold(allocationHash(g,leaf,domain),signatures);
  nonce++;id=g.id();require(allocations[id].status==0,"REPLAY");allocations[id]=Allocation(leaf,domain,g.epoch,g.amount,1);outstanding+=g.amount;epochEncumbered[g.epoch]+=g.amount;
  _send(domain,leaf,abi.encode(uint8(1),id,g));emit Allocated(id,leaf,g.amount);
 }
 function freezeHash(bytes32 id) public pure returns(bytes32){return keccak256(abi.encode(keccak256("FreezeQuota(bytes32 grantId)"),id));}
 function requestFreeze(bytes32 id,bytes[] calldata signatures) external {Allocation storage a=allocations[id];require(a.status==1,"NOT_ACTIVE");_threshold(freezeHash(id),signatures);a.status=2;_send(a.domain,a.leaf,abi.encode(uint8(2),id));emit FreezeRequested(id);}
 function resendFreeze(bytes32 id) external {Allocation memory a=allocations[id];require(a.status==2,"NOT_PENDING");_send(a.domain,a.leaf,abi.encode(uint8(2),id));}
 function handleReceiveFinalizedMessage(uint32 sourceDomain,bytes32 sender,uint32 finality,bytes calldata body) external returns(bool){
  _authenticate(finality);return _receive(sourceDomain,sender,body);
 }
 function handleReceiveLocalMessage(bytes calldata body) external returns(bool){return _receive(localDomain,bytes32(uint256(uint160(msg.sender))),body);}
 function _receive(uint32 sourceDomain,bytes32 sender,bytes calldata body) private returns(bool){
  (uint8 kind,bytes32 id,uint256 spent)=abi.decode(body,(uint8,bytes32,uint256));Allocation storage a=allocations[id];
  require(kind==3&&a.status==2&&a.domain==sourceDomain&&sender==bytes32(uint256(uint160(a.leaf)))&&spent<=a.amount,"WRONG_ACK");
  a.status=3;outstanding-=a.amount;finalizedSpent+=spent;epochEncumbered[a.epoch]-=a.amount-spent;emit Reclaimed(id,spent,a.amount-spent);return true;
 }
 function free() external view returns(uint256){return totalLimit-finalizedSpent-outstanding;}
}
