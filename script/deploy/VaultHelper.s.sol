// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";

import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";

// Copy of Vault.s.sol but made it easier to set all the parameters + comments
contract VaultHelper is Script {


    function run() public {

        // who owns the vault
        address owner = address(0xD0d7F8a5a86d8271ff87ff24145Cf40CEa9F7A39);

        // symbiotic provided helper contract to help initializing all the vault params
        // This will be different on different networks / testnets / devnets
        address vaultConfigurator = address(0xD2191FE92987171691d552C219b8caEf186eb9cA);

        // collateral wrappers can be deployed with the appropriate DefaultCollateralFactory contract for your target chain
        address collateral = address(0xBC9fD18dc74059E208a185889E364ECF554B873E);

        // slashing is only valid for one epoch. We will need to work with networks to figure out what kind of values they want
        // when withdrawing, you will wait a minimum of 1 vault epoch and a maximum of 2 vault epochs.
        uint48 epochDuration = 604800; // 7 days in seconds

        // do we want to allow only certain addresses to deposit
        bool depositWhitelist = false;
        address[] memory whitelistedDepositors;

        // do we want a maximum amount of collateral that can be deposited? Set to 0 if no limit
        // Never Enough!!!
        uint256 depositLimit = 0;

        // Do we want to specify a...
        // 0 -> NetworkRestakeDelegator
        // 1 -> FullRestakeDelegator
        // 2 -> OperatorSpecificDelegator
        uint64 delegatorIndex = 0;

        // do we want a dedicated slasher contract
        bool withSlasher = true;
        uint64 slasherIndex = 1; // 1 for VetoSlasher
        uint48 vetoDuration = 172800; // 2 days in seconds. Symbiotic recommends this value to be substantially lower than the vault epoch

        // Burner address. We can set this to the address of a contract if we need custom behavior
        address burner = address(0x0);
        bool isBurnerHook = false; // We need to toggle this on if we want a contract that has an on-slash callback

        // slashing callback. If we wish to use one of the premade hooks we should deploy them beforehand
        // https://github.com/symbioticfi/hooks/tree/main/test/networkRestakeDelegator
        address hook;

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        ///////////////////////////////////////////////////////////////////////////////
        ////////////////////////  BEGIN ORIGINAL SCRIPT ///////////////////////////////
        ///////////////////////////////////////////////////////////////////////////////

        bytes memory vaultParams = abi.encode(
            IVault.InitParams({
                collateral: collateral,
                burner: burner,
                epochDuration: epochDuration,
                depositWhitelist: depositWhitelist,
                isDepositLimit: depositLimit != 0,
                depositLimit: depositLimit,
                defaultAdminRoleHolder: depositWhitelist ? deployer : owner,
                depositWhitelistSetRoleHolder: owner,
                depositorWhitelistRoleHolder: owner,
                isDepositLimitSetRoleHolder: owner,
                depositLimitSetRoleHolder: owner
            })
        );

        uint256 roleHolders = 1;
        if (hook != address(0) && hook != owner) {
            roleHolders = 2;
        }
        address[] memory networkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](roleHolders);
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](roleHolders);
        networkLimitSetRoleHolders[0] = owner;
        operatorNetworkLimitSetRoleHolders[0] = owner;
        operatorNetworkSharesSetRoleHolders[0] = owner;
        if (roleHolders > 1) {
            networkLimitSetRoleHolders[1] = hook;
            operatorNetworkLimitSetRoleHolders[1] = hook;
            operatorNetworkSharesSetRoleHolders[1] = hook;
        }

        bytes memory delegatorParams;
        if (delegatorIndex == 0) {
            delegatorParams = abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                })
            );
        } else if (delegatorIndex == 1) {
            delegatorParams = abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operatorNetworkLimitSetRoleHolders: operatorNetworkLimitSetRoleHolders
                })
            );
        } else if (delegatorIndex == 2) {
            delegatorParams = abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: hook,
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operator: owner
                })
            );
        }

        bytes memory slasherParams;
        if (slasherIndex == 0) {
            slasherParams = abi.encode(
                ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: isBurnerHook})})
            );
        } else if (slasherIndex == 1) {
            slasherParams = abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({isBurnerHook: isBurnerHook}),
                    vetoDuration: vetoDuration,
                    resolverSetEpochsDelay: 3
                })
            );
        }

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(vaultConfigurator).create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: vaultParams,
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );

        if (depositWhitelist) {
            Vault(vault_).grantRole(Vault(vault_).DEFAULT_ADMIN_ROLE(), owner);
            Vault(vault_).grantRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);

            for (uint256 i; i < whitelistedDepositors.length; ++i) {
                Vault(vault_).setDepositorWhitelistStatus(whitelistedDepositors[i], true);
            }

            Vault(vault_).renounceRole(Vault(vault_).DEPOSITOR_WHITELIST_ROLE(), deployer);
            Vault(vault_).renounceRole(Vault(vault_).DEFAULT_ADMIN_ROLE(), deployer);
        }

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);
        console2.log("Slasher: ", slasher_);

        vm.stopBroadcast();
    }
}
