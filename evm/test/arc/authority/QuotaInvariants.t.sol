// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {GlobalQuotaRoot} from "../../../src/arc/quota/GlobalQuotaRoot.sol";
import {EndpointQuota} from "../../../src/arc/quota/EndpointQuota.sol";
import {QuotaTypes} from "../../../src/arc/quota/QuotaSync.sol";
import {ArcAuthorityDomain as Domain} from "../../../src/arc/authority/ArcAuthorityDomain.sol";
import {QuotaBusFixture} from "./Quota.t.sol";

/// Random interleavings of allocate / spend / freeze / out-of-order and duplicate message delivery / time.
/// The in-memory bus is a fixture, not a Circle attestation: this proves the quota accounting, not the transport.
contract QuotaHandler is Test {
    using QuotaTypes for QuotaTypes.Grant;
    GlobalQuotaRoot public immutable root;
    EndpointQuota public immutable leaf;
    QuotaBusFixture public immutable bus;
    uint256 immutable controllerKey;
    bytes32 immutable policyHash;
    bytes32 immutable asset;
    bytes32[] public ids;
    uint64[] public epochs;
    uint256 public successfulSpends;

    constructor(GlobalQuotaRoot r, EndpointQuota l, QuotaBusFixture b, uint256 key, bytes32 policy, bytes32 asset_) {
        root = r; leaf = l; bus = b; controllerKey = key; policyHash = policy; asset = asset_;
    }

    function idsLength() external view returns (uint256) { return ids.length; }
    function epochsLength() external view returns (uint256) { return epochs.length; }

    function _sign(bytes32 h) private view returns (bytes[] memory ss) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, Domain.at(h, block.chainid, address(root)));
        ss = new bytes[](1);
        ss[0] = abi.encodePacked(r, s, v);
    }

    function allocate(uint256 amount) external {
        uint64 epoch = uint64(block.timestamp / root.periodSeconds());
        uint256 epochEnd = (uint256(epoch) + 1) * root.periodSeconds();
        uint256 expiry = block.timestamp + 300;
        if (expiry >= epochEnd) expiry = epochEnd - 1;
        QuotaTypes.Grant memory g = QuotaTypes.Grant(policyHash, asset, leaf.endpointChain(), address(this), epoch, root.nonce(), uint64(expiry), bound(amount, 1, 45_000000));
        try root.allocate(g, address(leaf), 0, _sign(root.allocationHash(g, address(leaf), 0))) returns (bytes32 id) {
            ids.push(id);
            epochs.push(epoch);
        } catch {}
    }

    function spend(uint256 which, uint256 amount) external {
        if (ids.length == 0) return;
        try leaf.consume(ids[which % ids.length], bound(amount, 1, 20_000000)) { successfulSpends++; } catch {}
    }

    function freeze(uint256 which) external {
        if (ids.length == 0) return;
        bytes32 id = ids[which % ids.length];
        try root.requestFreeze(id, _sign(root.freezeHash(id))) {} catch {}
    }

    /// Any message index, any order, repeats allowed. Invalid or replayed deliveries must revert harmlessly.
    function deliver(uint256 which) external {
        uint256 n = bus.count();
        if (n == 0) return;
        try bus.deliver(which % n) {} catch {}
    }

    function advance(uint256 seconds_) external { vm.warp(block.timestamp + bound(seconds_, 0, 2500)); }
}

contract QuotaInvariants is Test {
    uint256 constant PK = uint256(keccak256("amane.test-only.quota-controller"));
    bytes32 constant BUDGET = keccak256("USDC six decimal budget");
    QuotaBusFixture bus;
    GlobalQuotaRoot root;
    EndpointQuota leaf;
    QuotaHandler handler;

    function setUp() public {
        vm.warp(1_800_000_000);
        bus = new QuotaBusFixture();
        address[] memory owners = new address[](1);
        owners[0] = vm.addr(PK);
        bytes32 policy = keccak256("policy");
        root = new GlobalQuotaRoot(address(bus), policy, BUDGET, 100_000000, 50_000000, 3600, 600, owners, 1);
        bus.setLocalDomain(0);
        // The handler plays the endpoint account (only the endpoint may consume).
        address endpointAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        leaf = new EndpointQuota(address(bus), address(root), 26, endpointAddr, keccak256("chain"), policy, BUDGET);
        handler = new QuotaHandler(root, leaf, bus, PK, policy, BUDGET);
        require(address(handler) == endpointAddr, "ENDPOINT_PREDICTION");
        bus.setDomain(address(root), 26);
        bus.setDomain(address(leaf), 0);
        targetContract(address(handler));
    }

    /// Global cap: spent + encumbered never exceeds the total, and free() is exact.
    function invariant_total_never_exceeded() public view {
        assertLe(root.finalizedSpent() + root.outstanding(), 100_000000);
        assertEq(root.free(), 100_000000 - root.finalizedSpent() - root.outstanding());
    }

    /// No epoch ever has more than the period limit encumbered.
    function invariant_period_limit_holds() public view {
        for (uint256 i; i < handler.epochsLength(); i++) assertLe(root.epochEncumbered(handler.epochs(i)), 50_000000);
    }

    /// Conservation: every unit is exactly one of free / outstanding (unreclaimed grant) / finalized spent,
    /// leaf spend never exceeds its grant, reclaimed spend equals what the leaf spent, and the root never
    /// finalizes more than the leaves actually spent.
    function invariant_grants_conserve_and_never_overspend() public view {
        uint256 outstanding; uint256 reclaimedSpent; uint256 leafSpentTotal;
        for (uint256 i; i < handler.idsLength(); i++) {
            bytes32 id = handler.ids(i);
            (, uint256 amount,, uint8 status) = _alloc(id);
            (uint256 issued, uint256 spent,,,) = leaf.balances(id);
            assertLe(spent, issued == 0 ? 0 : amount, "spent beyond grant");
            leafSpentTotal += spent;
            if (status == 1 || status == 2) outstanding += amount;
            if (status == 3) { reclaimedSpent += spent; assertLe(spent, amount); }
        }
        assertEq(root.outstanding(), outstanding, "outstanding mismatch");
        assertEq(root.finalizedSpent(), reclaimedSpent, "finalized spend mismatch");
        assertLe(root.finalizedSpent(), leafSpentTotal);
    }

    function _alloc(bytes32 id) private view returns (address l, uint256 amount, uint64 epoch, uint8 status) {
        (address leafAddr,, uint64 e, uint256 a, uint8 s) = root.allocations(id);
        return (leafAddr, a, e, s);
    }
}
