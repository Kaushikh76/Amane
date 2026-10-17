// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ArcAccount,IArcToken} from "./ArcAccount.sol";
import {ArcTypes as T} from "./ArcTypes.sol";

/// Isolated custody, not CCTP source authentication. Donations and mints are indistinguishable.
/// Capability MUST be VAULT_CUSTODY_OFFCHAIN_PROVENANCE; no source proof is asserted here.
contract IntentVault {
    ArcAccount public immutable account;
    address public immutable token;
    address public immutable recipient;
    address public immutable recovery;
    bytes32 public immutable actionHash;
    bytes32 public immutable rootHash;
    bytes32 public immutable leaseId;
    uint64 public immutable deadline;
    uint256 public immutable amount;
    bool public consumed;
    error Invalid();
    event Released(bytes32 indexed actionHash,uint256 amount);
    event Recovered(address indexed recovery,uint256 amount);
    constructor(ArcAccount account_,T.ActionIntent memory intent) {
        T.RootPolicy memory p=account_.rootPolicy();
        require(p.token==intent.token && p.recipient==intent.recipient && intent.amount>0 && intent.kind==9 && intent.deadline>=block.timestamp && p.adapterId==intent.adapterId,"scope");
        account=account_; token=intent.token; recipient=intent.recipient; recovery=p.recovery;
        actionHash=account_.actionHash(intent); rootHash=account_.rootHash(); leaseId=intent.leaseId; deadline=intent.deadline; amount=intent.amount;
    }
    function quarantined() public view returns(bool) {
        T.AgentLease memory l=account.lease(leaseId);
        return block.timestamp>deadline || block.timestamp>l.expiresAt || account.revoked(leaseId) || account.rootHash()!=rootHash;
    }
    function release(bytes32 h) external {
        if(msg.sender!=address(account) || h!=actionHash || consumed || quarantined()) revert Invalid();
        consumed=true; _transfer(recipient,amount); emit Released(h,amount);
    }
    function recover() external {
        if(msg.sender!=address(account) || !quarantined()) revert Invalid();
        // Surplus/donations are also recoverable only after the original intent cannot execute.
        consumed=true; uint256 balance=IArcToken(token).balanceOf(address(this));
        if(balance==0) revert Invalid(); _transfer(recovery,balance); emit Recovered(recovery,balance);
    }
    function _transfer(address to,uint256 value) private {
        (bool ok,bytes memory ret)=token.call(abi.encodeWithSelector(0xa9059cbb,to,value));
        if(!ok || (ret.length!=0 && (ret.length!=32 || !abi.decode(ret,(bool))))) revert Invalid();
    }
}
contract IntentVaultFactory {
    function predict(ArcAccount account,T.ActionIntent memory a) public view returns(address) {
        bytes32 salt=account.actionHash(a);
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),salt,keccak256(abi.encodePacked(type(IntentVault).creationCode,abi.encode(account,a))))))));
    }
    function create(ArcAccount account,T.ActionIntent memory a) external returns(address vault) {
        vault=predict(account,a);
        if(vault.code.length==0) vault=address(new IntentVault{salt:account.actionHash(a)}(account,a));
    }
}
