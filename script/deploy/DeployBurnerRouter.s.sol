// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {IBurnerRouterFactory} from "@symbioticfi-burners/src/interfaces/router/IBurnerRouterFactory.sol";
import {IBurnerRouter} from "@symbioticfi-burners/src/interfaces/router/IBurnerRouter.sol";

contract BurnerRouterScript is Script {

    /**
    *  source .env && forge script script/deploy/DeployBurnerRouter.s.sol:BurnerRouterScript --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
    */
    function run() public {
        
        // holesky deployed burner router
        address burnerRouterFactory = address(0x80154294963b0D81011706cc7f90bec6b7A68852);

        // manager of the routers receivers
        address owner = address(0xD0d7F8a5a86d8271ff87ff24145Cf40CEa9F7A39);

        // collateral asset of the vault
        address collateral = address(0xBC9fD18dc74059E208a185889E364ECF554B873E);

        // delay for the setting a new receiver; set to 1 epoch
        uint48 delay = 604800; // 7 days in seconds

        // default destination for slashed funds
        address globalReceiver = address(0x0);

        // to set slashers on a more granular level (don't set and use the default receiver)
        IBurnerRouter.NetworkReceiver[] memory networkReceivers = new IBurnerRouter.NetworkReceiver[](0);
        IBurnerRouter.OperatorNetworkReceiver[] memory operatorNetworkReceivers = new IBurnerRouter.OperatorNetworkReceiver[](0);

        vm.startBroadcast();

        address burnerRouter = IBurnerRouterFactory(burnerRouterFactory).create(
            IBurnerRouter.InitParams({
                owner: owner,
                collateral: collateral,
                delay: delay,
                globalReceiver: globalReceiver,
                networkReceivers: networkReceivers,
                operatorNetworkReceivers: operatorNetworkReceivers
            })
        );

        console2.log("Burner Router: ", burnerRouter);

        vm.stopBroadcast();
    }
}
