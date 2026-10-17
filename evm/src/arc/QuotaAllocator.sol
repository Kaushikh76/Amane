// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// Same-chain discrete authority accounting only. No cross-chain ack entry point exists.
/// This is not wired into ArcAccount expenditure and must not be advertised as a global spend cap.
contract QuotaLeaf {
    address public immutable root;
    address public immutable endpoint;
    uint256 public immutable issued;
    uint256 public spent;
    bool public frozen;
    error Forbidden();
    constructor(address endpoint_,uint256 amount) {root=msg.sender;endpoint=endpoint_;issued=amount;}
    function spend(uint256 amount) external {
        if(msg.sender!=endpoint || frozen || amount==0 || spent+amount>issued) revert Forbidden(); spent+=amount;
    }
    function close() external returns(uint256 used,uint256 remaining) {
        if(msg.sender!=root || frozen) revert Forbidden(); frozen=true; return(spent,issued-spent);
    }
}
contract QuotaAllocator {
    address public immutable owner;
    uint256 public immutable limit;
    uint256 public free;
    uint256 public outstanding;
    uint256 public finalizedSpent;
    mapping(bytes32 => QuotaLeaf) public leaves;
    mapping(bytes32 => bool) public closed;
    error Forbidden();
    constructor(uint256 limit_) {owner=msg.sender;limit=limit_;free=limit_;}
    function allocate(bytes32 id,address endpoint,uint256 amount) external returns(QuotaLeaf leaf) {
        if(msg.sender!=owner || address(leaves[id])!=address(0) || endpoint==address(0) || amount==0 || amount>free) revert Forbidden();
        free-=amount;outstanding+=amount;leaf=new QuotaLeaf(endpoint,amount);leaves[id]=leaf;
    }
    function reclaim(bytes32 id) external {
        if(msg.sender!=owner || address(leaves[id])==address(0) || closed[id]) revert Forbidden();
        closed[id]=true;
        (uint256 used,uint256 remaining)=leaves[id].close();
        outstanding-=used+remaining;finalizedSpent+=used;free+=remaining;
    }
}
