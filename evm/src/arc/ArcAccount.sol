// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ArcTypes as T} from "./ArcTypes.sol";
import {AmaneSig} from "../AmaneTypes.sol";
import {AdapterRegistry, IAmaneAdapter} from "../AdapterRegistry.sol";

interface IArcToken {
    function balanceOf(address) external view returns(uint256);
    function decimals() external view returns(uint8);
}
interface IIntentVault {
    function release(bytes32 actionHash) external;
    function recover() external;
}

/// Versioned port of the existing account's signature, registry, checks-effects-interactions and
/// independently measured PAY path. No v1 source or domain changed. Unsupported actions fail closed.
contract ArcAccount {
    uint256 public immutable deploymentChainId;
    AdapterRegistry public immutable registry;
    uint8 public immutable threshold;
    mapping(address => bool) public controller;
    bytes32 public rootHash;
    T.RootPolicy public root;
    mapping(bytes32 => T.AgentLease) private leases;
    mapping(bytes32 => bool) public leaseSeen;
    mapping(bytes32 => bool) public revoked;
    mapping(bytes32 => mapping(uint256 => bool)) public nonceUsed;
    mapping(bytes32 => uint256) public totalSpent;
    mapping(bytes32 => mapping(uint256 => uint256)) public periodSpent;
    uint256 public controlNonce;
    uint256 public pauseEpoch;
    bool public paused;
    bool private entered;
    error Rejected(bytes32 reason);
    event PolicyInstalled(bytes32 indexed rootHash,uint64 version);
    event LeaseActivated(bytes32 indexed leaseId,bytes32 rootHash,address agent);
    event Executed(bytes32 indexed digest,bytes32 indexed leaseId,uint256 nonce,address token,address recipient,uint256 amount,uint256 fee);
    event LeaseRevoked(bytes32 indexed leaseId);
    event PauseChanged(bool paused,uint256 epoch);

    constructor(address[] memory owners,uint8 quorum,AdapterRegistry registry_) {
        if ((block.chainid != 5042002 && block.chainid != 31337) || address(registry_).code.length == 0) revert Rejected("CHAIN_OR_REGISTRY");
        if (quorum == 0 || quorum > owners.length) revert Rejected("THRESHOLD");
        address last;
        for(uint256 i;i<owners.length;++i) {
            if(owners[i] <= last) revert Rejected("CONTROLLER_ORDER");
            controller[owners[i]]=true; last=owners[i];
        }
        threshold=quorum; registry=registry_; deploymentChainId=block.chainid;
    }
    modifier lock() { if(entered) revert Rejected("REENTRANCY"); entered=true; _; entered=false; }
    modifier owner() { if(!controller[msg.sender]) revert Rejected("CONTROLLER"); _; }
    function domainSeparator() public view returns(bytes32) {
        return keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),keccak256("Amane Arc"),keccak256("2"),block.chainid,address(this)));
    }
    function digest(bytes32 structHash) public view returns(bytes32) { return keccak256(abi.encodePacked(hex"1901",domainSeparator(),structHash)); }
    function actionHash(T.ActionIntent memory a) public view returns(bytes32) { return digest(T.hash(a)); }
    function policyHash(T.RootPolicy memory p) public view returns(bytes32) { return digest(T.hash(p)); }
    function leaseHash(T.AgentLease memory l) public view returns(bytes32) { return digest(T.hash(l)); }
    function controlHash(bytes32 operation,address target,uint64 deadline) public view returns(bytes32) {
        return digest(keccak256(abi.encode(T.CONTROL_TYPEHASH,operation,target,controlNonce,deadline)));
    }
    function _threshold(bytes32 h,bytes[] calldata sigs) private view {
        address last; uint256 count;
        for(uint256 i;i<sigs.length;++i) {
            address s=AmaneSig.recover(h,sigs[i]);
            if(s<=last || !controller[s]) revert Rejected("THRESHOLD_SIGNATURE"); last=s; ++count;
        }
        if(count<threshold) revert Rejected("THRESHOLD_SIGNATURE");
    }
    function installPolicy(T.RootPolicy calldata p,uint64 deadline,bytes[] calldata sigs) external lock {
        if(block.chainid!=deploymentChainId || block.timestamp>deadline) revert Rejected("CHAIN_OR_DEADLINE");
        if(block.chainid==5042002 && p.token!=address(0x3600000000000000000000000000000000000000)) revert Rejected("ASSET_IDENTITY");
        if(p.version!=root.version+1 || p.token.code.length==0 || IArcToken(p.token).decimals()!=6 || p.recipient==address(0) || p.recipient==address(this) || p.recovery==address(0)) revert Rejected("POLICY");
        if(p.perAction==0 || p.perAction>p.perPeriod || p.perPeriod>p.total || p.periodSeconds==0 || p.maxLeaseLifetime==0) revert Rejected("CAPS");
        AdapterRegistry.Entry memory e=registry.get(p.adapterId);
        if(e.adapter==address(0) || e.actionKind!=9 || e.adapter.codehash!=e.codeHash) revert Rejected("ADAPTER");
        bytes32 h=policyHash(p);
        // Include expiry and control nonce alongside policy hash; a withheld old install expires.
        _threshold(digest(keccak256(abi.encode(T.CONTROL_TYPEHASH,h,address(this),controlNonce,deadline))),sigs);
        ++controlNonce; root=p; rootHash=h; emit PolicyInstalled(h,p.version);
    }
    function activateLease(T.AgentLease calldata l,bytes[] calldata sigs) external lock {
        T.RootPolicy memory p=root;
        if(rootHash==0 || l.rootHash!=rootHash || leaseSeen[l.leaseId] || revoked[l.leaseId] || l.leaseId==0 || l.agent==address(0) || controller[l.agent]) revert Rejected("LEASE");
        if(l.expiresAt<=l.validAfter || l.expiresAt<block.timestamp || l.expiresAt-l.validAfter>p.maxLeaseLifetime) revert Rejected("WINDOW");
        if(l.perAction==0 || l.perAction>l.perPeriod || l.perPeriod>l.total || l.perAction>p.perAction || l.perPeriod>p.perPeriod || l.total>p.total) revert Rejected("CAPS");
        _threshold(leaseHash(l),sigs); leases[l.leaseId]=l; leaseSeen[l.leaseId]=true; emit LeaseActivated(l.leaseId,l.rootHash,l.agent);
    }
    function rootPolicy() external view returns(T.RootPolicy memory) { return root; }
    function lease(bytes32 id) external view returns(T.AgentLease memory) {return leases[id];}
    function leaseLive(bytes32 id) public view returns(bool) {
        T.AgentLease memory l=leases[id];
        return !paused && leaseSeen[id] && !revoked[id] && l.rootHash==rootHash && block.timestamp>=l.validAfter && block.timestamp<=l.expiresAt && block.chainid==deploymentChainId;
    }
    function revoke(bytes32 id) external owner {revoked[id]=true; emit LeaseRevoked(id);}
    function pause() external owner {paused=true; ++pauseEpoch; emit PauseChanged(true,pauseEpoch);}
    function unpause(uint64 deadline,bytes[] calldata sigs) external lock {
        if(!paused || block.timestamp>deadline) revert Rejected("PAUSE");
        _threshold(controlHash(keccak256(abi.encode("UNPAUSE",pauseEpoch)),address(this),deadline),sigs);
        ++controlNonce; paused=false; emit PauseChanged(false,pauseEpoch);
    }
    function _debit(bytes32 bucket,uint256 amount,uint256 perAction,uint256 perPeriod,uint256 total,uint64 period) private {
        uint256 epoch=block.timestamp/period;
        if(amount>perAction || periodSpent[bucket][epoch]+amount>perPeriod || totalSpent[bucket]+amount>total) revert Rejected("BUDGET");
        periodSpent[bucket][epoch]+=amount; totalSpent[bucket]+=amount;
    }
    function _authorize(T.ActionIntent calldata a,bytes calldata sig) private returns(bytes32 h) {
        if(!leaseLive(a.leaseId) || block.timestamp>a.deadline) revert Rejected("LEASE_OR_DEADLINE");
        T.RootPolicy memory p=root; T.AgentLease memory l=leases[a.leaseId];
        if(a.kind!=9 || a.token!=p.token || a.recipient!=p.recipient || a.adapterId!=p.adapterId || a.amount==0) revert Rejected("SCOPE");
        // The first release supports sponsorship only, without reimbursements. Nonzero fees fail closed.
        if(a.maxFee!=0 || a.feeRecipient!=address(0)) revert Rejected("FEE_UNSUPPORTED");
        h=actionHash(a);
        if(AmaneSig.recover(h,sig)!=l.agent || nonceUsed[a.leaseId][a.nonce]) revert Rejected("SIGNATURE_OR_NONCE");
        nonceUsed[a.leaseId][a.nonce]=true;
        _debit(keccak256(abi.encode("root",rootHash)),a.amount,p.perAction,p.perPeriod,p.total,p.periodSeconds);
        _debit(keccak256(abi.encode("lease",a.leaseId)),a.amount,l.perAction,l.perPeriod,l.total,p.periodSeconds);
    }
    function execute(T.ActionIntent calldata a,bytes calldata sig) external lock returns(bytes32 h) {
        h=_authorize(a,sig); T.RootPolicy memory p=root;
        AdapterRegistry.Entry memory e=registry.get(p.adapterId);
        if(e.adapter.codehash!=e.codeHash || e.actionKind!=9) revert Rejected("ADAPTER_CODE");
        uint256 beforeBalance=IArcToken(a.token).balanceOf(address(this));
        uint256 beforeRecipient=IArcToken(a.token).balanceOf(a.recipient);
        _transfer(a.token,e.adapter,a.amount);
        IAmaneAdapter(e.adapter).execute(a.token,a.token,a.amount,a.amount,a.recipient);
        if(beforeBalance-IArcToken(a.token).balanceOf(address(this))!=a.amount || IArcToken(a.token).balanceOf(a.recipient)-beforeRecipient!=a.amount) revert Rejected("MEASUREMENT");
        emit Executed(h,a.leaseId,a.nonce,a.token,a.recipient,a.amount,0);
    }
    function executeVault(T.ActionIntent calldata a,bytes calldata sig,address vault) external lock returns(bytes32 h) {
        h=_authorize(a,sig);
        uint256 beforeRecipient=IArcToken(a.token).balanceOf(a.recipient);
        IIntentVault(vault).release(h);
        if(IArcToken(a.token).balanceOf(a.recipient)-beforeRecipient!=a.amount) revert Rejected("MEASUREMENT");
        emit Executed(h,a.leaseId,a.nonce,a.token,a.recipient,a.amount,0);
    }
    function recoverVault(address vault,uint64 deadline,bytes[] calldata sigs) external lock {
        if(block.timestamp>deadline) revert Rejected("DEADLINE");
        _threshold(controlHash(keccak256("RECOVER_VAULT"),vault,deadline),sigs); ++controlNonce; IIntentVault(vault).recover();
    }
    function withdraw(uint256 amount,uint64 deadline,bytes[] calldata sigs) external lock {
        if(block.timestamp>deadline) revert Rejected("DEADLINE");
        _threshold(controlHash(keccak256(abi.encode("WITHDRAW",rootHash,amount)),root.recovery,deadline),sigs);
        ++controlNonce; _transfer(root.token,root.recovery,amount);
    }
    function _transfer(address token,address to,uint256 amount) private {
        (bool ok,bytes memory ret)=token.call(abi.encodeWithSelector(0xa9059cbb,to,amount));
        if(!ok || (ret.length!=0 && (ret.length!=32 || !abi.decode(ret,(bool))))) revert Rejected("TRANSFER");
    }
}
