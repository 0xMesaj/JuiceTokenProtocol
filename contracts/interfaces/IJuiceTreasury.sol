// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IERC20.sol";

interface IJuiceTreasury{
    function sendEther(address payable, uint256) external;
    function sendToken(IERC20, address, uint256) external;

}