// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    ActionIntent,
    ActionKinds,
    AgentLease,
    AmaneHash,
    AmaneSig,
    AssetLimit,
    DestSpec,
    DestSpecHash,
    LeaseEndpoint,
    LeaseIssuer,
    PauseAccount,
    PolicyEndpoint,
    RevokeLease,
    RootPolicy,
    UnpauseAccount,
    Withdraw
} from "../../AmaneTypes.sol";
import {AdapterRegistry, IAmaneAdapter} from "../../AdapterRegistry.sol";
import {AmaneStorage, IAmaneBridge, IAmaneTransport, IERC20Minimal} from "../../AmaneStorage.sol";
import {AuthorityFees} from "./AuthorityFees.sol";
import {ArcAuthorityStorage} from "./ArcAuthorityStorage.sol";
import {ArcAuthorityDomain as Domain} from "./ArcAuthorityDomain.sol";
import {Codes} from "../../AmaneCodes.sol";

/// Non-upgradeable Amane endpoint for one logical account on one EVM chain.
/// Invariant: Action ⊆ Lease ⊆ RootPolicy. Every agent action is verified, budget-debited and
/// nonce-marked before any token leaves the account, and output is measured by the account itself.
interface IAuthorityBridgeRoute {function destinationSpecHash() external view returns(bytes32);}
interface IAuthorityPreparation {function sweepDonation() external;}
interface IAuthorityQuota {function consume(bytes32 id,uint256 amount) external;}
contract ArcAuthority is ArcAuthorityStorage {
    uint256 public immutable deploymentChainId;
    bytes32 public immutable accountId;
    bytes32 public immutable chainRef;
    AdapterRegistry public immutable registry;
    uint8 public immutable threshold;
    /// Pinned extension holding the controller-only policy installer and the cross-chain receiver.
    address public immutable ext;
    bytes32 private immutable extCodeHash;
    /// Versioned full authority endpoint: PAY, SWAP, BRIDGE and ESCROW_FUND.
    uint32 public constant CORE_VERSION = 4;
    uint32 public constant AUTHORITY_VERSION = 3;
    uint8 internal constant ESCROW_FUND = 11;

    using AmaneHash for *;


    constructor(bytes32 accountId_, address[] memory controllers_, uint8 threshold_, AdapterRegistry registry_, address ext_) {
        require(block.chainid==5042002 || block.chainid==11155111 || block.chainid==31337,"UNSUPPORTED_CHAIN");
        if (ext_.code.length == 0) revert AmaneRejected(Codes.ADAPTER_UNKNOWN);
        deploymentChainId=block.chainid;
        ext = ext_;
        extCodeHash = ext_.codehash;
        if (controllers_.length == 0 || threshold_ == 0 || threshold_ > controllers_.length) {
            revert AmaneRejected(Codes.CONTROLLER_BAD_THRESHOLD);
        }
        for (uint256 i; i < controllers_.length; ++i) {
            if (i > 0 && controllers_[i] <= controllers_[i - 1]) revert AmaneRejected(Codes.CONTROLLER_UNSORTED);
            if (controllers_[i] == address(0)) revert AmaneRejected(Codes.CONTROLLER_ZERO);
            isController[controllers_[i]] = true;
        }
        controllerList = controllers_;
        accountId = accountId_;
        threshold = threshold_;
        registry = registry_;
        chainRef = registry_.chainRef();
    }

    function domainSeparator() external view returns(bytes32) { return Domain.separator(block.chainid,address(this)); }
    function signingDigest(bytes32 structHash) external view returns(bytes32) { return Domain.digest(structHash); }

    function controllers() external view returns (address[] memory) {
        return controllerList;
    }


    // ---------------------------------------------------------------- root controller paths


    /// Reduction path: one controller signature suffices and anyone may relay it, so an executor
    /// cannot censor a pause by refusing to submit. A pause is bound to the current pause epoch,
    /// which only a threshold unpause advances, so controllers cannot exhaust it and old pause
    /// signatures die after the next unpause.
    function pause(PauseAccount calldata x, bytes calldata sig) external {
        if (x.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        if (x.pauseEpoch != pauseEpoch) revert AmaneRejected(Codes.REPLAY_PAUSE_EPOCH);
        if (block.timestamp > x.deadline) revert AmaneRejected(Codes.ACTION_EXPIRED);
        address signer = AmaneSig.recover(Domain.digest(x.hash()), sig);
        if (!isController[signer]) revert AmaneRejected(Codes.CONTROLLER_NOT_AUTHORIZED);
        // Single-use ids: replaying an earlier pause must not restore it as `lastPauseId`, or a
        // withheld unpause for that earlier pause would lift the current one.
        if (pauseIdUsed[x.pauseId]) revert AmaneRejected(Codes.REPLAY_PAUSE_EPOCH);
        pauseIdUsed[x.pauseId] = true;
        paused = true;
        lastPauseId = x.pauseId;
        emit Paused(x.pauseEpoch, x.pauseId, signer);
    }

    /// An unpause lifts only the exact pause its signers saw: any later pause changes
    /// `lastPauseId` and invalidates a withheld unpause.
    function unpause(UnpauseAccount calldata x, bytes[] calldata sigs) external nonReentrant {
        if (x.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        if (x.chainRef != chainRef || x.account != self32()) revert AmaneRejected(Codes.ACTION_WRONG_ENDPOINT);
        if (!paused || x.pauseEpoch != pauseEpoch || x.pauseId != lastPauseId) {
            revert AmaneRejected(Codes.REPLAY_PAUSE_EPOCH);
        }
        if (block.timestamp > x.deadline) revert AmaneRejected(Codes.ACTION_EXPIRED);
        _requireThreshold(Domain.digest(x.hash()), sigs);
        paused = false;
        pauseEpoch = x.pauseEpoch + 1;
        emit Unpaused(x.pauseEpoch, x.pauseId);
    }

    function revokeLease(RevokeLease calldata x, bytes calldata sig) external {
        if (x.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        address signer = AmaneSig.recover(Domain.digest(x.hash()), sig);
        Lease storage l = leases[x.leaseId];
        bool allowed = isController[signer] || (l.status == LEASE_ACTIVE && l.issuer == signer);
        if (!allowed) revert AmaneRejected(Codes.CONTROLLER_NOT_AUTHORIZED);
        l.status = LEASE_REVOKED;
        emit LeaseRevoked(x.leaseId, signer);
    }

    function withdraw(Withdraw calldata x, bytes[] calldata sigs) external nonReentrant {
        if (x.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        if (x.chainRef != chainRef || x.account != self32()) revert AmaneRejected(Codes.ACTION_WRONG_ENDPOINT);
        if (x.opNonce != opNonce) revert AmaneRejected(Codes.REPLAY_OP_NONCE);
        if (block.timestamp > x.deadline) revert AmaneRejected(Codes.ACTION_EXPIRED);
        if (!recoveryDestination[policyVersion][x.destination]) revert AmaneRejected(Codes.OWNER_DESTINATION_NOT_ALLOWED);
        _requireThreshold(Domain.digest(x.hash()), sigs);
        opNonce = x.opNonce + 1;
        address to = _asAddress(x.destination);
        address token = _asAddress(x.assetId);
        // Recovery may take available and quarantined funds, never a live reservation.
        uint256 live = reservedOf[token] - quarantinedOf[token];
        if (IERC20Minimal(token).balanceOf(address(this)) - live < x.amount) revert AmaneRejected(Codes.XCHAIN_RESERVED_FUNDS);
        uint256 q = x.amount < quarantinedOf[token] ? x.amount : quarantinedOf[token];
        quarantinedOf[token] -= q;
        reservedOf[token] -= q;
        _safeTransfer(token, to, x.amount);
        emit Withdrawn(x.assetId, x.amount, to, x.opNonce);
    }

    // ---------------------------------------------------------------- lease issuance

    function activateLease(AgentLease calldata l, bytes calldata sig) external nonReentrant {
        if(block.chainid!=deploymentChainId)revert AmaneRejected(Codes.ACTION_WRONG_ENDPOINT);
        if (l.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        uint64 v = policyVersion;
        if (v == 0 || l.policyVersion != v) revert AmaneRejected(Codes.POLICY_VERSION_MISMATCH);
        if (l.authMode != AUTH_MODE_AGENT_SIGNED) revert AmaneRejected(Codes.LEASE_BAD_AUTH_MODE);
        if (l.expiresAt <= l.validAfter) revert AmaneRejected(Codes.LEASE_BAD_WINDOW);
        if (block.timestamp > l.activateBefore) revert AmaneRejected(Codes.LEASE_ACTIVATION_EXPIRED);
        uint64 lifetime = l.expiresAt - l.validAfter;
        if (lifetime > maxLeaseLifetime) revert AmaneRejected(Codes.LEASE_LIFETIME_EXCEEDED);
        if (l.allowedActions & ~allowedActions != 0) revert AmaneRejected(Codes.LEASE_ACTION_NOT_IN_ROOT);
        if (leases[l.leaseId].status != LEASE_NONE) revert AmaneRejected(Codes.REPLAY_LEASE_ID);

        address signer = AmaneSig.recover(Domain.digest(l.hash()), sig);
        if (signer != l.issuer) revert AmaneRejected(Codes.LEASE_ISSUER_NOT_AUTHORIZED);
        if (l.agent == l.issuer || isController[l.agent]) revert AmaneRejected(Codes.LEASE_AGENT_IS_ISSUER);
        bool byController = isController[signer];
        IssuerPolicy memory ip = issuers[v][signer];
        if (!byController) {
            if (!ip.allowed) revert AmaneRejected(Codes.LEASE_ISSUER_NOT_AUTHORIZED);
            if (lifetime > ip.maxLeaseLifetime) revert AmaneRejected(Codes.LEASE_LIFETIME_EXCEEDED);
            if (!issuerAgents[v][signer][l.agent]) revert AmaneRejected(Codes.LEASE_AGENT_NOT_ALLOWED);
        }

        LeaseEndpoint calldata e = l.endpoints[_ownLeaseEndpoint(l)];
        bytes32 id = l.leaseId;
        for (uint256 i; i < e.adapters.length; ++i) {
            if (!rootAdapters[v][e.adapters[i]].allowed) revert AmaneRejected(Codes.LEASE_ADAPTER_NOT_IN_ROOT);
            if (leaseAdapters[id][e.adapters[i]]) revert AmaneRejected(Codes.LEASE_DUPLICATE_ENTRY);
            leaseAdapters[id][e.adapters[i]] = true;
        }
        for (uint256 i; i < e.assets.length; ++i) {
            AssetLimit calldata a = e.assets[i];
            Limit storage r = rootAssets[v][a.assetId];
            if (!r.allowed) revert AmaneRejected(Codes.LEASE_ASSET_NOT_IN_ROOT);
            if (a.maxPerAction > r.perAction || a.maxPerEpoch > r.perEpoch || a.maxTotal > r.total) {
                revert AmaneRejected(Codes.LEASE_CAP_EXCEEDS_ROOT);
            }
            if (!byController) {
                Limit storage c = issuerLimits[v][signer][a.assetId];
                if (a.maxPerAction > c.perAction || a.maxPerEpoch > c.perEpoch || a.maxTotal > c.total) {
                    revert AmaneRejected(Codes.LEASE_CAP_EXCEEDS_ISSUER);
                }
            }
            Limit storage dst = leaseAssets[id][a.assetId];
            if (dst.allowed) revert AmaneRejected(Codes.LEASE_DUPLICATE_ENTRY);
            _storeLimit(dst, a);
        }
        for (uint256 i; i < e.recipients.length; ++i) {
            if (rootRecipientLabel[v][e.recipients[i]] == 0) revert AmaneRejected(Codes.LEASE_RECIPIENT_NOT_IN_ROOT);
            if (leaseRecipients[id][e.recipients[i]]) revert AmaneRejected(Codes.LEASE_DUPLICATE_ENTRY);
            leaseRecipients[id][e.recipients[i]] = true;
        }
        for (uint256 i; i < e.beneficiaries.length; ++i) {
            if (rootBeneficiaryLabel[v][e.beneficiaries[i]] == 0) revert AmaneRejected(Codes.LEASE_BENEFICIARY_NOT_IN_ROOT);
            if (leaseBeneficiaries[id][e.beneficiaries[i]]) revert AmaneRejected(Codes.LEASE_DUPLICATE_ENTRY);
            leaseBeneficiaries[id][e.beneficiaries[i]] = true;
        }

        leases[id] = Lease({
            status: LEASE_ACTIVE,
            byController: byController,
            policyVersion: v,
            agent: l.agent,
            issuer: signer,
            validAfter: l.validAfter,
            expiresAt: l.expiresAt,
            allowedActions: l.allowedActions
        });
        emit LeaseActivated(id, l.agent, signer, l.expiresAt);
    }

    // ---------------------------------------------------------------- agent action path


    /// Spends an intent reservation while enforcing this endpoint's independent budgets.
    function executeReserved(bytes32 intent, ActionIntent calldata a, bytes calldata agentSig) external nonReentrant returns (uint256) {
        Reservation memory r = reservations[intent];
        if (r.remaining == 0) revert AmaneRejected(Codes.XCHAIN_NO_RESERVATION);
        if (block.timestamp > r.deadline) revert AmaneRejected(Codes.XCHAIN_EXPIRED);
        if (a.leaseId != r.leaseId || (a.planHash != intent && r.actionKind != ActionKinds.BRIDGE) || a.actionKind != r.actionKind || a.adapterId != r.adapterId || a.recipient != r.recipient || a.assetIn != r.asset || a.amountIn > r.remaining) {
            revert AmaneRejected(Codes.XCHAIN_RESERVATION_MISMATCH);
        }
        reservations[intent].remaining = r.remaining - a.amountIn;
        reservedOf[_asAddress(r.asset)] -= a.amountIn;
        return _execute(a, agentSig, true);
    }


    event FeeReimbursed(bytes32 indexed leaseId,bytes32 indexed actionDigest,address indexed recipient,uint256 amount);
    function feePolicy(bytes32 leaseId) external view returns(FeeState memory){return feePolicies[leaseId];}
    function executeActionWithFee(ActionIntent calldata a,bytes calldata actionSig,AuthorityFees.Intent calldata f,bytes calldata feeSig) external nonReentrant returns(uint256 output) {
        uint256 gasStart=gasleft();FeeState storage state=feePolicies[a.leaseId];AuthorityFees.Policy memory p=state.policy;
        bytes32 digest=Domain.digest(a.hash());Lease memory l=leases[a.leaseId];
        require(state.hash!=0&&p.rootHash==policyHash&&f.feePolicyHash==state.hash&&f.actionDigest==digest&&msg.sender==p.recipient&&f.amount>0,"WRONG_FEE_INTENT");
        require(AmaneSig.recover(Domain.digest(AuthorityFees.hash(f)),feeSig)==l.agent,"FEE_AGENT");
        uint64 period=uint64(block.timestamp/p.periodSeconds);uint256 periodSpent=state.period==period?state.periodSpent:0;
        require(f.amount<=p.perAction&&periodSpent+f.amount<=p.perPeriod&&state.totalSpent+f.amount<=p.total,"FEE_CAP");
        bytes32 asset=bytes32(uint256(uint160(p.token)));
        // Principal and fee share the same authority caps. Per-action applies to the combined debit.
        uint256 combined=f.amount+(asset==a.assetIn?a.amountIn:0);
        require(combined<=leaseAssets[a.leaseId][asset].perAction&&combined<=rootAssets[policyVersion][asset].perAction,"COMBINED_ACTION_CAP");
        if(!l.byController)require(combined<=issuerLimits[policyVersion][l.issuer][asset].perAction,"COMBINED_ISSUER_CAP");
        output=_execute(a,actionSig,false);
        // Arc native USDC has 18 decimals; reimbursement ERC20 has 6. Never reimburse beyond measured gas.
        require(block.chainid==5042002||block.chainid==31337,"FEE_CHAIN");
        require(p.token==address(0x3600000000000000000000000000000000000000)||block.chainid==31337,"FEE_TOKEN");
        uint256 units=gasStart-gasleft();if(units>p.maxGasUnits)units=p.maxGasUnits;
        uint256 price=tx.gasprice<p.maxGasPrice?tx.gasprice:p.maxGasPrice;
        require(f.amount<=units*price/1e12,"UNMEASURED_FEE");
        state.period=period;state.periodSpent=periodSpent+f.amount;state.totalSpent+=f.amount;
        _debitAll(a.leaseId,l,policyVersion,asset,f.amount);
        require(IERC20Minimal(p.token).balanceOf(address(this))-reservedOf[p.token]>=f.amount,"RESERVED_FEE");
        uint256 beforeBalance=IERC20Minimal(p.token).balanceOf(address(this));uint256 beforeRecipient=IERC20Minimal(p.token).balanceOf(p.recipient);
        _safeTransfer(p.token,p.recipient,f.amount);
        require(beforeBalance-IERC20Minimal(p.token).balanceOf(address(this))==f.amount&&IERC20Minimal(p.token).balanceOf(p.recipient)-beforeRecipient==f.amount,"FEE_NOT_EXACT");
        emit FeeReimbursed(a.leaseId,digest,p.recipient,f.amount);
    }

    function executeAction(ActionIntent calldata a, bytes calldata agentSig) external nonReentrant returns (uint256) {
        return _execute(a, agentSig, false);
    }

    function _execute(ActionIntent calldata a, bytes calldata agentSig, bool reserved) private returns (uint256 amountOut) {
        if(block.chainid!=deploymentChainId)revert AmaneRejected(Codes.ACTION_WRONG_ENDPOINT);
        if (paused) revert AmaneRejected(Codes.ACTION_ACCOUNT_PAUSED);
        if (a.accountId != accountId) revert AmaneRejected(Codes.POLICY_WRONG_ACCOUNT);
        if (a.chainRef != chainRef || a.account != self32()) revert AmaneRejected(Codes.ACTION_WRONG_ENDPOINT);
        Lease memory l = leases[a.leaseId];
        if (l.status != LEASE_ACTIVE) revert AmaneRejected(Codes.LEASE_NOT_ACTIVE);
        uint64 v = policyVersion;
        if (a.policyVersion != v || l.policyVersion != v) revert AmaneRejected(Codes.POLICY_VERSION_MISMATCH);
        if (block.timestamp < l.validAfter) revert AmaneRejected(Codes.LEASE_NOT_YET_VALID);
        if (block.timestamp > l.expiresAt) revert AmaneRejected(Codes.LEASE_EXPIRED);
        if (block.timestamp > a.deadline) revert AmaneRejected(Codes.ACTION_EXPIRED);

        bytes32 digest = Domain.digest(a.hash());
        if (AmaneSig.recover(digest, agentSig) != l.agent) {
            revert AmaneRejected(Codes.ACTION_WRONG_AGENT);
        }
        if (nonceUsed[a.leaseId][a.nonce]) revert AmaneRejected(Codes.REPLAY_NONCE);
        nonceUsed[a.leaseId][a.nonce] = true;

        if (a.actionKind >= 32 || (l.allowedActions >> a.actionKind) & 1 == 0 || (allowedActions >> a.actionKind) & 1 == 0) {
            revert AmaneRejected(Codes.ACTION_KIND_NOT_ALLOWED);
        }
        AdapterRegistry.Entry memory entry = _checkAdapter(a, v);

        if (a.amountIn == 0) revert AmaneRejected(Codes.ACTION_ZERO_AMOUNT);
        // Authorization checks run before budgets so a rejection names the real reason; the whole
        // call reverts either way, so ordering never changes what is allowed.
        uint256 minOut = _authorizeKind(a, v);
        address tokenIn = _asAddress(a.assetIn);
        _debitAll(a.leaseId, l, v, a.assetIn, a.amountIn);
        if (!reserved) {
            // Reserved arrivals belong to their intents; ordinary actions spend only what is left.
            if (IERC20Minimal(tokenIn).balanceOf(address(this)) - reservedOf[tokenIn] < a.amountIn) revert AmaneRejected(Codes.XCHAIN_RESERVED_FUNDS);
        }
        if (a.actionKind == ActionKinds.SWAP) amountOut = _swap(a, entry.adapter, tokenIn, minOut);
        else if (a.actionKind == ActionKinds.BRIDGE) amountOut = _bridge(a, entry.adapter, tokenIn, digest);
        else amountOut = _deliver(a, entry.adapter, tokenIn);

        emit ActionExecuted(a.leaseId, a.nonce, a.adapterId, a.actionKind, a.amountIn, amountOut, a.planHash, a.planStep);
    }

    // ---------------------------------------------------------------- extension-served entry points

    function installFeePolicy(AuthorityFees.Policy calldata,bytes[] calldata) external {_delegate();}
    function bindQuota(bytes32,bytes32,address,bytes32,uint64,uint64,bytes[] calldata) external {_delegate();}
    function installPolicy(RootPolicy calldata, bytes[] calldata) external {
        _delegate();
    }

    function receiveCrossChain(ActionIntent calldata, bytes calldata, DestSpec calldata, bytes32, bytes calldata) external {
        _delegate();
    }

    function releaseReservation(bytes32) external {
        _delegate();
    }

    function recoverArrival(ActionIntent calldata, bytes calldata, DestSpec calldata, bytes32, bytes calldata) external {
        _delegate();
    }

    /// Runs the same call in this account's storage using the extension pinned at construction.
    function _delegate() private {
        address e = ext;
        if (e.codehash != extCodeHash) revert AmaneRejected(Codes.ADAPTER_CODE_CHANGED);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), e, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }

    // ---------------------------------------------------------------- views

    function lease(bytes32 leaseId) external view returns (Lease memory) {
        return leases[leaseId];
    }

    function leaseBudget(bytes32 leaseId, bytes32 assetId) external view returns (Limit memory limit, Spend memory spent) {
        return (leaseAssets[leaseId][assetId], leaseSpend[leaseId][assetId]);
    }

    function rootBudget(bytes32 assetId) external view returns (Limit memory limit, Spend memory spent) {
        return (rootAssets[policyVersion][assetId], rootSpend[policyVersion][assetId]);
    }

    // ---------------------------------------------------------------- internals

    function _checkAdapter(ActionIntent calldata a, uint64 v) private view returns (AdapterRegistry.Entry memory entry) {
        if (!leaseAdapters[a.leaseId][a.adapterId]) revert AmaneRejected(Codes.ACTION_ADAPTER_NOT_ALLOWED);
        AdapterPolicy memory ap = rootAdapters[v][a.adapterId];
        if (!ap.allowed) revert AmaneRejected(Codes.ACTION_ADAPTER_NOT_ALLOWED);
        if (ap.nameHash != keccak256(bytes(a.adapterName)) || ap.version != a.adapterVersion) {
            revert AmaneRejected(Codes.ACTION_ADAPTER_NAME_MISMATCH);
        }
        entry = registry.get(a.adapterId);
        if (entry.adapter == address(0)) revert AmaneRejected(Codes.ADAPTER_UNKNOWN);
        if (entry.nameHash != ap.nameHash || entry.adapterVersion != ap.version) {
            revert AmaneRejected(Codes.ACTION_ADAPTER_NAME_MISMATCH);
        }
        if (entry.actionKind != a.actionKind) revert AmaneRejected(Codes.ADAPTER_KIND_MISMATCH);
        if (entry.adapter.codehash != entry.codeHash) revert AmaneRejected(Codes.ADAPTER_CODE_CHANGED);
    }

    function _debitAll(bytes32 leaseId, Lease memory l, uint64 v, bytes32 assetId, uint256 amount) private {
        QuotaBinding memory quota=quotaBindings[v][assetId];
        require(!quotaRequired[assetId]||quota.leaf!=address(0),"QUOTA_BINDING_REQUIRED");
        if(quota.leaf!=address(0)) {require(quota.leaf.codehash==quota.codeHash,"QUOTA_CODE_CHANGED");IAuthorityQuota(quota.leaf).consume(quota.grantId,amount);}
        Limit memory ll = leaseAssets[leaseId][assetId];
        if (!ll.allowed) revert AmaneRejected(Codes.ACTION_ASSET_NOT_ALLOWED);
        _debit(leaseSpend[leaseId][assetId], ll, amount);
        _debit(rootSpend[v][assetId], rootAssets[v][assetId], amount);
        if (!l.byController) {
            _debit(issuerSpend[v][l.issuer][assetId], issuerLimits[v][l.issuer][assetId], amount);
        }
    }

    function _debit(Spend storage s, Limit memory lim, uint256 amount) private {
        if (amount > lim.perAction) revert AmaneRejected(Codes.BUDGET_PER_ACTION);
        uint256 level = _level(s, lim.perEpoch);
        if (amount > level) revert AmaneRejected(Codes.BUDGET_EPOCH);
        uint256 t = s.totalSpent + amount;
        if (t > lim.total) revert AmaneRejected(Codes.BUDGET_TOTAL);
        s.initialized = true;
        s.updatedAt = uint64(block.timestamp);
        s.level = level - amount;
        s.totalSpent = t;
    }

    /// Strict fixed-period capacity; unlike v1, this endpoint does not refill within an epoch.
    function _level(Spend memory s, uint256 capacity) private view returns (uint256) {
        if (!s.initialized || s.updatedAt / epochSeconds != block.timestamp / epochSeconds) return capacity;
        return s.level;
    }

    function _authorizeKind(ActionIntent calldata a, uint64 v) private view returns (uint256 minOut) {
        if (a.actionKind == ActionKinds.SWAP) {
            if (a.assetOut == a.assetIn) revert AmaneRejected(Codes.ACTION_ASSET_NOT_ALLOWED);
            if (!leaseAssets[a.leaseId][a.assetOut].allowed) revert AmaneRejected(Codes.ACTION_ASSET_NOT_ALLOWED);
            if (a.recipient != bytes32(0)) revert AmaneRejected(Codes.ACTION_RECIPIENT_NOT_ALLOWED);
            Floor memory f = swapFloor[v][keccak256(abi.encode(a.assetIn, a.assetOut))];
            if (f.den == 0) revert AmaneRejected(Codes.ACTION_NO_PRICE_FLOOR);
            uint256 required = (a.amountIn * f.num + f.den - 1) / f.den;
            return a.minAmountOut > required ? a.minAmountOut : required;
        }
        if (a.actionKind == ActionKinds.BRIDGE) {
            if(!policyDestinations[v][a.recipient] || a.recipient==self32())revert AmaneRejected(Codes.XCHAIN_WRONG_DESTINATION);
            // Only to another endpoint of this account that the owner pinned as a recipient; the
            // destination endpoint enforces what the funds may be used for (planHash = dest spec).
            if (!leaseRecipients[a.leaseId][a.recipient] || rootRecipientLabel[v][a.recipient] != keccak256(bytes(a.recipientLabel))) {
                revert AmaneRejected(Codes.ACTION_RECIPIENT_NOT_ALLOWED);
            }
            return 0;
        }
        if (a.actionKind == ActionKinds.PAY || a.actionKind == ESCROW_FUND) {
            if (a.assetOut != a.assetIn) revert AmaneRejected(Codes.ACTION_ASSET_NOT_ALLOWED);
            if (!leaseRecipients[a.leaseId][a.recipient]) revert AmaneRejected(Codes.ACTION_RECIPIENT_NOT_ALLOWED);
            if (rootRecipientLabel[v][a.recipient] != keccak256(bytes(a.recipientLabel))) {
                revert AmaneRejected(Codes.ACTION_RECIPIENT_NOT_ALLOWED);
            }
            return a.amountIn;
        }
        revert AmaneRejected(Codes.ACTION_KIND_NOT_ALLOWED);
    }

    function _swap(ActionIntent calldata a, address adapter, address tokenIn, uint256 minOut) private returns (uint256 out) {
        address tokenOut = _asAddress(a.assetOut);
        uint256 inBefore = IERC20Minimal(tokenIn).balanceOf(address(this));
        uint256 outBefore = IERC20Minimal(tokenOut).balanceOf(address(this));
        _safeTransfer(tokenIn, adapter, a.amountIn);
        IAmaneAdapter(adapter).execute(tokenIn, tokenOut, a.amountIn, minOut, address(this));
        uint256 inAfter = IERC20Minimal(tokenIn).balanceOf(address(this));
        uint256 outAfter = IERC20Minimal(tokenOut).balanceOf(address(this));
        if (inBefore - inAfter != a.amountIn) revert AmaneRejected(Codes.ACTION_OVERSPENT);
        out = outAfter - outBefore;
        if (out < minOut) revert AmaneRejected(Codes.ACTION_BELOW_MIN_OUT);
    }


    /// BRIDGE: the adapter hands exactly amountIn to the transport with payload (intent, destination
    /// account). The account measures that exactly amountIn left and the adapter kept nothing.
    function _bridge(ActionIntent calldata a, address adapter, address tokenIn, bytes32 intent) private returns (uint256) {
        require(IAuthorityBridgeRoute(adapter).destinationSpecHash()==a.planHash,"BRIDGE_SPEC_MISMATCH");
        IAuthorityPreparation(adapter).sweepDonation();
        uint256 inBefore = IERC20Minimal(tokenIn).balanceOf(address(this));
        _safeTransfer(tokenIn, adapter, a.amountIn);
        IAmaneBridge(adapter).bridge(tokenIn, a.amountIn, a.recipient, intent);
        if (inBefore - IERC20Minimal(tokenIn).balanceOf(address(this)) != a.amountIn || IERC20Minimal(tokenIn).balanceOf(adapter) != 0) {
            revert AmaneRejected(Codes.ACTION_OVERSPENT);
        }
        return a.amountIn;
    }

    function _deliver(ActionIntent calldata a, address adapter, address tokenIn) private returns (uint256 delivered) {
        if(a.actionKind==ESCROW_FUND)IAuthorityPreparation(adapter).sweepDonation();
        address to = _asAddress(a.recipient);
        uint256 inBefore = IERC20Minimal(tokenIn).balanceOf(address(this));
        uint256 toBefore = IERC20Minimal(tokenIn).balanceOf(to);
        _safeTransfer(tokenIn, adapter, a.amountIn);
        IAmaneAdapter(adapter).execute(tokenIn, tokenIn, a.amountIn, a.amountIn, to);
        if (inBefore - IERC20Minimal(tokenIn).balanceOf(address(this)) != a.amountIn) {
            revert AmaneRejected(Codes.ACTION_OVERSPENT);
        }
        delivered = IERC20Minimal(tokenIn).balanceOf(to) - toBefore;
        if (delivered != a.amountIn) revert AmaneRejected(Codes.ACTION_UNDER_DELIVERED);
    }


    function _ownLeaseEndpoint(AgentLease calldata l) private view returns (uint256 idx) {
        bytes32 me = self32();
        bool found;
        for (uint256 i; i < l.endpoints.length; ++i) {
            if (l.endpoints[i].chainRef == chainRef && l.endpoints[i].account == me) {
                if (found) revert AmaneRejected(Codes.LEASE_DUPLICATE_ENTRY);
                idx = i;
                found = true;
            }
        }
        if (!found) revert AmaneRejected(Codes.LEASE_WRONG_ENDPOINT);
    }



    function _storeLimit(Limit storage l, AssetLimit calldata a) private {
        if(a.maxPerAction>a.maxPerEpoch || a.maxPerEpoch>a.maxTotal)revert AmaneRejected(Codes.LEASE_CAP_EXCEEDS_ROOT);
        l.allowed = true;
        l.perAction = a.maxPerAction;
        l.perEpoch = a.maxPerEpoch;
        l.total = a.maxTotal;
    }

    function _requireThreshold(bytes32 digest, bytes[] calldata sigs) private view {
        address last;
        uint256 count;
        for (uint256 i; i < sigs.length; ++i) {
            address s = AmaneSig.recover(digest, sigs[i]);
            if (s <= last) revert AmaneRejected(Codes.CONTROLLER_UNSORTED);
            if (!isController[s]) revert AmaneRejected(Codes.CONTROLLER_NOT_AUTHORIZED);
            last = s;
            ++count;
        }
        if (count < threshold) revert AmaneRejected(Codes.CONTROLLER_THRESHOLD);
    }


    function _safeTransfer(address token, address to, uint256 amount) private {
        if (token.code.length == 0) revert AmaneRejected(Codes.ASSET_NOT_A_TOKEN);
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!ok || (ret.length != 0 && (ret.length != 32 || abi.decode(ret, (uint256)) != 1))) {
            revert AmaneRejected(Codes.ASSET_TRANSFER_FAILED);
        }
    }
}
