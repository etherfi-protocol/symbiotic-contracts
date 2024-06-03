// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Registry} from "./base/Registry.sol";

import {IOperatorRegistry} from "src/interfaces/IOperatorRegistry.sol";

contract OperatorRegistry is Registry, IOperatorRegistry {
    /**
     * @inheritdoc IOperatorRegistry
     */
    function registerOperator() external {
        if (isEntity(msg.sender)) {
            revert OperatorAlreadyRegistered();
        }

        _addEntity(msg.sender);
    }
}