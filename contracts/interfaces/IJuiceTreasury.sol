// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IERC20.sol";

interface IJuiceTreasury{
    function initializeTreasury( uint256 _amount ) external;
}
