// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyAdmin as OZProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title ProxyAdmin
 * @notice Local wrapper for OpenZeppelin's ProxyAdmin
 * @dev This contract simply inherits from OpenZeppelin's implementation
 */
contract ProxyAdmin is OZProxyAdmin {
    constructor(address owner_) OZProxyAdmin(owner_) {}
}
