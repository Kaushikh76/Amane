// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {RootPolicy,AgentLease,AmaneHash} from "../../../src/AmaneTypes.sol";
import {ArcAuthorityDomain as Domain} from "../../../src/arc/authority/ArcAuthorityDomain.sol";
contract AuthorityGoldenTest is Test {
 using AmaneHash for *;
 function policyHash(RootPolicy calldata p) external pure returns(bytes32){return p.hash();}
 function leaseHash(AgentLease calldata l) external pure returns(bytes32){return l.hash();}
 function test_thirty_full_struct_hash_and_domain_vectors() public view {
  string memory json=vm.readFile("../vectors/authority-v3.json");
  for(uint256 i;i<30;i++){
   string memory path=string.concat(".vectors[",vm.toString(i),"].");bytes memory encoded=vm.parseJsonBytes(json,string.concat(path,"encoded"));
   uint256 kind=vm.parseJsonUint(json,string.concat(path,"kind"));bytes32 hash=kind==0?this.policyHash(abi.decode(encoded,(RootPolicy))):this.leaseHash(abi.decode(encoded,(AgentLease)));
   assertEq(hash,vm.parseJsonBytes32(json,string.concat(path,"structHash")));
   uint256 chainId=vm.parseJsonUint(json,string.concat(path,"chainId"));address account=vm.parseJsonAddress(json,string.concat(path,"account"));
   assertEq(Domain.at(hash,chainId,account),vm.parseJsonBytes32(json,string.concat(path,"digest")));
  }
 }
}
