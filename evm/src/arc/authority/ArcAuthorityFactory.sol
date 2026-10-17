// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ArcAuthority} from "./ArcAuthority.sol";
import {AdapterRegistry} from "../../AdapterRegistry.sol";
/// Inert bytecode storage. Splitting keeps both stores and the CREATE2 factory under EIP-170.
contract AuthorityCodeStore {
 constructor(bytes memory data){bytes memory runtime=abi.encodePacked(bytes1(0),data);assembly("memory-safe"){return(add(runtime,32),mload(runtime))}}
}
contract ArcAuthorityFactory {
 AdapterRegistry public immutable registry;address public immutable extension;bytes32 public immutable extensionCodeHash;
 address public immutable codeFirst;address public immutable codeSecond;bytes32 public immutable creationCodeHash;
 event Created(address indexed account,bytes32 indexed logicalAccountId,bytes32 salt);
 constructor(AdapterRegistry registry_,address extension_){
  require(address(registry_).code.length>0&&extension_.code.length>0,"MISSING_INFRASTRUCTURE");registry=registry_;extension=extension_;extensionCodeHash=extension_.codehash;
  bytes memory code=type(ArcAuthority).creationCode;creationCodeHash=keccak256(code);uint256 cut=code.length/2;bytes memory first=new bytes(cut);bytes memory second=new bytes(code.length-cut);
  for(uint256 i;i<code.length;i++){if(i<cut)first[i]=code[i];else second[i-cut]=code[i];}
  codeFirst=address(new AuthorityCodeStore(first));codeSecond=address(new AuthorityCodeStore(second));
 }
 function salt(bytes32 accountId,address[] memory owners,uint8 threshold,bytes32 userSalt) public view returns(bytes32){return keccak256(abi.encode(block.chainid,accountId,owners,threshold,userSalt));}
 function _creationCode() private view returns(bytes memory code){address a=codeFirst;address b=codeSecond;uint256 first=a.code.length-1;uint256 second=b.code.length-1;code=new bytes(first+second);assembly("memory-safe"){extcodecopy(a,add(code,32),1,first) extcodecopy(b,add(add(code,32),first),1,second)}require(keccak256(code)==creationCodeHash,"CREATION_CODE_CHANGED");}
 function _init(bytes32 accountId,address[] memory owners,uint8 threshold) private view returns(bytes memory){return abi.encodePacked(_creationCode(),abi.encode(accountId,owners,threshold,registry,extension));}
 function predict(bytes32 accountId,address[] memory owners,uint8 threshold,bytes32 userSalt) public view returns(address){bytes32 initHash=keccak256(_init(accountId,owners,threshold));bytes32 h=keccak256(abi.encodePacked(bytes1(0xff),address(this),salt(accountId,owners,threshold,userSalt),initHash));return address(uint160(uint256(h)));}
 function create(bytes32 accountId,address[] memory owners,uint8 threshold,bytes32 userSalt) external returns(address account){
  require(extension.codehash==extensionCodeHash,"EXTENSION_CHANGED");account=predict(accountId,owners,threshold,userSalt);if(account.code.length>0)return account;
  bytes memory init=_init(accountId,owners,threshold);bytes32 deploymentSalt=salt(accountId,owners,threshold,userSalt);assembly("memory-safe"){account:=create2(0,add(init,32),mload(init),deploymentSalt)}require(account!=address(0),"CREATE_FAILED");emit Created(account,accountId,userSalt);
 }
}
