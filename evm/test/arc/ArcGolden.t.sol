// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {ArcTypes as T} from "../../src/arc/ArcTypes.sol";
contract ArcGoldenTest is Test {
 function digest(bytes32 h) internal pure returns(bytes32) {bytes32 d=keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),keccak256("Amane Arc"),keccak256("2"),uint256(31337),address(100)));return keccak256(abi.encodePacked(hex"1901",d,h));}
 function test_typescript_solidity_policy_lease_action_domains() public view {
  string memory json=vm.readFile("../vectors/arc-v2.json");
  T.RootPolicy memory p=T.RootPolicy(1,address(1),address(2),bytes32(uint256(3)),address(4),20,40,100,100,1000);
  bytes32 rootHash=digest(T.hash(p));assertEq(rootHash,vm.parseJsonBytes32(json,".rootHash"));
  T.AgentLease memory l=T.AgentLease(bytes32(uint256(5)),rootHash,address(6),1000,2000,10,30,80);assertEq(digest(T.hash(l)),vm.parseJsonBytes32(json,".leaseHash"));
  T.ActionIntent memory a=T.ActionIntent(l.leaseId,1,9,address(1),address(2),bytes32(uint256(3)),10,1900,0,address(0),bytes32(uint256(7)));assertEq(digest(T.hash(a)),vm.parseJsonBytes32(json,".actionHash"));
  assertEq(T.ROOT_TYPEHASH,vm.parseJsonBytes32(json,".typeHashes.RootPolicy"));assertEq(T.LEASE_TYPEHASH,vm.parseJsonBytes32(json,".typeHashes.AgentLease"));assertEq(T.ACTION_TYPEHASH,vm.parseJsonBytes32(json,".typeHashes.ActionIntent"));
 }
}
