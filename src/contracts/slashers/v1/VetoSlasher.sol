// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IVetoSlasher} from "src/interfaces/slashers/v1/IVetoSlasher.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {IOptInService} from "src/interfaces/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract VetoSlasher is NonMigratableEntity, AccessControlUpgradeable, IVetoSlasher {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint256 public SHARES_BASE = 10 ** 18;

    /**
     * @inheritdoc IVetoSlasher
     */
    bytes32 public constant RESOLVER_SHARES_SET_ROLE = keccak256("RESOLVER_SHARES_SET_ROLE");

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public vault;

    /**
     * @inheritdoc IVetoSlasher
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public executeDuration;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public resolversSetDelay;

    mapping(address network => Resolvers resolvers) private _resolvers;

    mapping(address network => DelayedResolvers resolvers) private _nextResolvers;

    modifier onlyNetworkMiddleware(address network) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }
        _;
    }

    constructor(
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        _disableInitializers();

        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        NETWORK_VAULT_OPT_IN_SERVICE = networkVaultOptInService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    function resolversIn(address network, uint48 duration) public view returns (address[] memory) {
        return _getResolversAt(_resolvers[network], _nextResolvers[network], Time.timestamp() + duration).values();
    }

    function resolvers(address network) public view returns (address[] memory) {
        return _getResolversAt(_resolvers[network], _nextResolvers[network], Time.timestamp()).values();
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverSharesIn(address network, address resolver, uint48 duration) public view returns (uint256) {
        return
            _getResolversSharesAt(_resolvers[network], _nextResolvers[network], Time.timestamp() + duration)[resolver];
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverShares(address network, address resolver) public view returns (uint256) {
        return _getResolversSharesAt(_resolvers[network], _nextResolvers[network], Time.timestamp())[resolver];
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function requestSlash(
        address network,
        address operator,
        uint256 amount
    ) external onlyNetworkMiddleware(network) returns (uint256 slashIndex) {
        if (amount == 0) {
            revert InsufficientSlash();
        }

        if (!IOptInService(NETWORK_VAULT_OPT_IN_SERVICE).isOptedIn(network, vault)) {
            revert NetworkNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(
                operator,
                vault,
                IVault(vault).currentEpoch() != 0
                    ? IVault(vault).previousEpochStart()
                    : IVault(vault).currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(
                operator,
                network,
                IVault(vault).currentEpoch() != 0
                    ? IVault(vault).previousEpochStart()
                    : IVault(vault).currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInNetwork();
        }

        uint48 vetoDeadline = Time.timestamp() + vetoDuration;
        uint48 executeDeadline = vetoDeadline + executeDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                operator: operator,
                amount: amount,
                vetoDeadline: vetoDeadline,
                executeDeadline: executeDeadline,
                vetoedShares: 0,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, operator, amount, vetoDeadline, executeDeadline);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > Time.timestamp()) {
            revert VetoPeriodNotEnded();
        }

        if (request.executeDeadline <= Time.timestamp()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        address delegator = IVault(vault).delegator();

        slashedAmount =
            Math.min(request.amount, IDelegator(delegator).operatorNetworkStake(request.network, request.operator));

        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

        if (slashedAmount != 0) {
            IVault(vault).slash(slashedAmount);

            IDelegator(delegator).onSlash(request.network, request.operator, slashedAmount);
        }

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function vetoSlash(uint256 slashIndex) external {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        uint256 resolverShares_ = resolverShares(request.network, msg.sender);

        if (resolverShares_ == 0) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        uint256 vetoedShares_ = request.vetoedShares + resolverShares_;

        request.vetoedShares = vetoedShares_;
        if (vetoedShares_ == SHARES_BASE) {
            request.completed = true;
        }

        emit VetoSlash(slashIndex);
    }

    function setResolvers(
        address network,
        address[] calldata resolvers,
        uint256[] calldata shares
    ) external onlyNetworkMiddleware(network) {
        if (resolvers.length != shares.length) {
            revert InvalidResolversLength();
        }

        Resolvers storage currentResolvers = _resolvers[network];
        DelayedResolvers storage nextResolvers = _nextResolvers[network];

        uint48 delay = _stakeIsDelegated(network) ? resolversSetDelay : 2 * IVault(vault).epochDuration();

        uint256 length;
        if (nextResolvers.timestamp != 0) {
            if (nextResolvers.timestamp <= Time.timestamp()) {
                length = currentResolvers.addressSet.length();
                for (uint256 i; i < length; ++i) {
                    address resolver = currentResolvers.addressSet.at(i);
                    currentResolvers.shares[resolver] = 0;
                    currentResolvers.addressSet.remove(resolver);
                }

                length = nextResolvers.addressSet.length();
                for (uint256 i; i < length; ++i) {
                    currentResolvers.addressSet.add(nextResolvers.addressSet.at(i));
                }
            }

            length = nextResolvers.addressSet.length();
            for (uint256 i; i < length; ++i) {
                address resolver = nextResolvers.addressSet.at(i);
                nextResolvers.shares[resolver] = 0;
                nextResolvers.addressSet.remove(resolver);
            }
        }

        uint256 totalShares;
        length = resolvers.length;
        for (uint256 i; i < length; ++i) {
            nextResolvers.addressSet.add(resolvers[i]);
            nextResolvers.shares[nextResolvers.addressSet.at(i)] = shares[i];

            totalShares += shares[i];
        }
        nextResolvers.timestamp = IVault(vault).currentEpochStart() + delay;

        if (totalShares != SHARES_BASE) {
            revert InvalidTotalShares();
        }

        emit SetResolvers(network, resolvers, shares);
    }

    function _getResolversAt(
        Resolvers storage resolvers,
        DelayedResolvers storage nextResolvers,
        uint48 timestamp
    ) private view returns (EnumerableSet.AddressSet storage) {
        if (nextResolvers.timestamp == 0 || timestamp < nextResolvers.timestamp) {
            return resolvers.addressSet;
        }
        return nextResolvers.addressSet;
    }

    function _getResolversSharesAt(
        Resolvers storage resolvers,
        DelayedResolvers storage nextResolvers,
        uint48 timestamp
    ) private view returns (mapping(address resolver => uint256) storage) {
        if (nextResolvers.timestamp == 0 || timestamp < nextResolvers.timestamp) {
            return resolvers.shares;
        }
        return nextResolvers.shares;
    }

    function _stakeIsDelegated(address network) private view returns (bool) {
        address delegator = IVault(vault).delegator();
        uint48 epochDuration = IVault(vault).epochDuration();
        return Math.max(
            Math.max(
                IDelegator(delegator).maxNetworkStake(network),
                IDelegator(delegator).maxNetworkStakeIn(network, epochDuration)
            ),
            IDelegator(delegator).maxNetworkStakeIn(network, 2 * epochDuration)
        ) != 0;
    }

    function _initialize(bytes memory data) internal override {
        (IVetoSlasher.InitParams memory params) = abi.decode(data, (IVetoSlasher.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        uint48 epochDuration = IVault(vault).epochDuration();
        if (params.vetoDuration + params.executeDuration > epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.resolversSetEpochsDelay < 3) {
            revert InvalidResolversSetEpochsDelay();
        }

        vault = params.vault;

        vetoDuration = params.vetoDuration;
        executeDuration = params.executeDuration;

        resolversSetDelay = (params.resolversSetEpochsDelay * epochDuration).toUint48();

        _grantRole(RESOLVER_SHARES_SET_ROLE, Ownable(params.vault).owner());
    }
}
