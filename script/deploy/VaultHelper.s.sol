// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IVetoSlasher} from "../../src/interfaces/slasher/IVetoSlasher.sol";

// Copy of Vault.s.sol but made it easier to set all the parameters + comments
contract VaultHelper is Script {


    function run() public {

        // who owns the vault
        address owner = address(0xD0d7F8a5a86d8271ff87ff24145Cf40CEa9F7A39);

        // symbiotic provided helper contract to help initializing all the vault params
        address vaultConfigurator = address(0x382e9c6fF81F07A566a8B0A3622dc85c47a891Df);

        // collateral wrappers can be deployed with the appropriate DefaultCollateralFactory contract for your target chain
        address collateral = address(0x1C495D4D20444Eb78E0026335cd5CFbD805ceD12);

        // slashing is only valid for one epoch. We will need to work with networks to figure out what kind of values they want
        uint48 epochDuration = 42069; // TODO

        // do we want to allow only certain addresses to deposit
        bool depositWhitelist = false;

        // do we want a maximum amount of collateral that can be deposited? Set to 0 if no limit
        uint256 depositLimit = 0;

        // Do we want to specify a...
        // 0 -> NetworkRestakeDelegator
        // 1 -> FullRestakeDelegator
        // 2 -> OperatorSpecificDelegator
        uint64 delegatorIndex = 0;

        // do we want a dedicated slasher contract
        bool withSlasher = false; // TODO: deploy a slasher
        uint64 slasherIndex = 1; // 1 for VetoSlasher
        uint48 vetoDuration = 100000; // TODO: what vetoDuration do networks want?

        // set roles that can perform certain key actions on the vault
        // Leave these arrays empty if you want no one to be able to perform the action
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkLimitSetRoleHolders = new address[](1);
        operatorNetworkLimitSetRoleHolders[0] = owner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = owner;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        bytes memory delegatorParams;
        if (delegatorIndex == 0) {
            delegatorParams = abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: owner,
                        hook: address(0),
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
                        hook: address(0),
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
                        hook: address(0),
                        hookSetRoleHolder: owner
                    }),
                    networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                    operator: owner
                })
            );
        }

        bytes memory slasherParams;
        if (slasherIndex == 1) {
            slasherParams = abi.encode(IVetoSlasher.InitParams({vetoDuration: vetoDuration, resolverSetEpochsDelay: 3}));
        }

        (address vault_, address delegator_, address slasher_) = IVaultConfigurator(vaultConfigurator).create(
            IVaultConfigurator.InitParams({
                version: IMigratablesFactory(IVaultConfigurator(vaultConfigurator).VAULT_FACTORY()).lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: epochDuration,
                        depositWhitelist: depositWhitelist,
                        isDepositLimit: depositLimit != 0,
                        depositLimit: depositLimit,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: owner,
                        depositorWhitelistRoleHolder: owner,
                        isDepositLimitSetRoleHolder: owner,
                        depositLimitSetRoleHolder: owner
                    })
                ),
                delegatorIndex: delegatorIndex,
                delegatorParams: delegatorParams,
                withSlasher: withSlasher,
                slasherIndex: slasherIndex,
                slasherParams: slasherParams
            })
        );

        console2.log("Vault: ", vault_);
        console2.log("Delegator: ", delegator_);
        console2.log("Slasher: ", slasher_);

        vm.stopBroadcast();
    }
}
