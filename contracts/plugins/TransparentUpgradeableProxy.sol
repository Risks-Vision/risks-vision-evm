// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TransparentUpgradeableProxy as OZProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TransparentUpgradeableProxy
 * @notice Local wrapper for OpenZeppelin's TransparentUpgradeableProxy
 * @dev This contract simply inherits from OpenZeppelin's implementation
 */
contract TransparentUpgradeableProxy is OZProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) OZProxy(_logic, admin_, _data) {}
}
