// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Vault} from "src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "src/interfaces/vault/IVault.sol";
import {SimpleCollateral} from "./mocks/SimpleCollateral.sol";
import {Token} from "./mocks/Token.sol";
import {VaultConfigurator} from "src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

contract VaultConfiguratorTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    DelegatorFactory delegatorFactory;
    SlasherFactory slasherFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    OptInService networkVaultOptInService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    SimpleCollateral collateral;
    VaultConfigurator vaultConfigurator;

    Vault vault;
    NetworkRestakeDelegator networkRestakeDelegator;
    Slasher slasher;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(networkRegistry),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create(
        address owner_,
        address burner,
        uint48 epochDuration,
        uint256 slasherSetEpochsDelay,
        bool depositWhitelist,
        bool withSlasher
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        slasherSetEpochsDelay = bound(slasherSetEpochsDelay, 3, type(uint256).max);
        vm.assume(owner_ != address(0));

        (address vault_, address networkRestakeDelegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner_,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: burner,
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: slasherSetEpochsDelay,
                    depositWhitelist: depositWhitelist,
                    defaultAdminRoleHolder: address(100),
                    slasherSetRoleHolder: address(101),
                    depositorWhitelistRoleHolder: address(102)
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: address(103)}),
                        networkLimitSetRoleHolder: address(104),
                        operatorNetworkSharesSetRoleHolder: address(105)
                    })
                ),
                withSlasher: withSlasher,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        vault = Vault(vault_);
        networkRestakeDelegator = NetworkRestakeDelegator(networkRestakeDelegator_);
        slasher = Slasher(slasher_);

        assertEq(vault.owner(), owner_);
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), networkRestakeDelegator_);
        assertEq(vault.slasher(), withSlasher ? slasher_ : address(0));
        assertEq(vault.burner(), burner);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.slasherSetEpochsDelay(), slasherSetEpochsDelay);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(100)), true);
        assertEq(vault.hasRole(vault.SLASHER_SET_ROLE(), address(101)), !withSlasher);
        assertEq(vault.hasRole(vault.DEPOSITOR_WHITELIST_ROLE(), address(102)), depositWhitelist);

        assertEq(networkRestakeDelegator.vault(), vault_);
        assertEq(networkRestakeDelegator.hasRole(networkRestakeDelegator.DEFAULT_ADMIN_ROLE(), address(103)), true);
        assertEq(networkRestakeDelegator.hasRole(networkRestakeDelegator.NETWORK_LIMIT_SET_ROLE(), address(104)), true);
        assertEq(
            networkRestakeDelegator.hasRole(networkRestakeDelegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), address(105)),
            true
        );

        if (withSlasher) {
            assertEq(slasher.vault(), vault_);
        }
    }
}