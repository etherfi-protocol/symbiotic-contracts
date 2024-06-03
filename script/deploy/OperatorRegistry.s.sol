// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";

contract OperatorRegistryScript is Script {
    function run() public {
        vm.startBroadcast();

        new OperatorRegistry();

        vm.stopBroadcast();
    }
}