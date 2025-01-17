// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {NetworkRestakeResetHook} from "../../lib/hooks/src/contracts/networkRestakeDelegator/NetworkRestakeResetHook.sol";

contract HookHelper is Script {

    function run() public {

        uint48 period = 604800; // period length in seconds
        uint256 slash_count = 2; // how many times you can be slashed in a given period before your stake is lowered

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        NetworkRestakeResetHook hook = new NetworkRestakeResetHook(period, slash_count);
        console2.log("hook deployed:", address(hook));

        vm.stopBroadcast();
    }
}
