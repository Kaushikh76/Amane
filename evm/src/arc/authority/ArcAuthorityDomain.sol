// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ActionIntent} from "../../AmaneTypes.sol";
library ArcAuthorityDomain {
    bytes32 internal constant DOMAIN_TYPEHASH=keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    function separator(uint256 chainId,address endpoint) internal pure returns(bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH,keccak256("Amane Arc"),keccak256("3"),chainId,endpoint));
    }
    function digest(bytes32 h) internal view returns(bytes32) {return at(h,block.chainid,address(this));}
    function at(bytes32 h,uint256 chainId,address endpoint) internal pure returns(bytes32) {return keccak256(abi.encodePacked(hex"1901",separator(chainId,endpoint),h));}
    function source(bytes32 h,ActionIntent calldata a) internal pure returns(bytes32) {
        uint256 chainId;
        if(a.chainRef==keccak256("eip155:5042002"))chainId=5042002;
        else if(a.chainRef==keccak256("eip155:11155111"))chainId=11155111;
        else if(a.chainRef==keccak256("eip155:31337"))chainId=31337;
        else revert("UNSUPPORTED_SOURCE_DOMAIN");
        if(uint256(a.account)>>160!=0)revert("BAD_SOURCE_ENDPOINT");
        return at(h,chainId,address(uint160(uint256(a.account))));
    }
}
