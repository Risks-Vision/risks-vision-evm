// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Uniswap Factory Interface (Uniswap V2 compatible)
// Version 2 of the Uniswap Factory
interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}