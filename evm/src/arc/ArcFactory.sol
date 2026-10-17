// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ArcAccount} from "./ArcAccount.sol";
import {AdapterRegistry} from "../AdapterRegistry.sol";
contract ArcFactory {
    AdapterRegistry public immutable registry;
    event AccountCreated(address indexed account,bytes32 indexed salt);
    constructor(AdapterRegistry registry_) { registry=registry_; }
    function initCode(address[] memory owners,uint8 threshold) public view returns(bytes memory) {
        return abi.encodePacked(type(ArcAccount).creationCode,abi.encode(owners,threshold,registry));
    }
    function salt(address[] memory owners,uint8 threshold,bytes32 userSalt) public view returns(bytes32) {
        return keccak256(abi.encode(block.chainid,owners,threshold,userSalt));
    }
    function predict(address[] memory owners,uint8 threshold,bytes32 userSalt) public view returns(address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),salt(owners,threshold,userSalt),keccak256(initCode(owners,threshold)))))));
    }
    function create(address[] memory owners,uint8 threshold,bytes32 userSalt) external returns(address account) {
        account=predict(owners,threshold,userSalt);
        if(account.code.length!=0) return account;
        account=address(new ArcAccount{salt:salt(owners,threshold,userSalt)}(owners,threshold,registry));
        emit AccountCreated(account,salt(owners,threshold,userSalt));
    }
}
