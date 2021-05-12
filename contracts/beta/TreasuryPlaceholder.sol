// SPDX-License-Identifier: MIT
pragma solidity >0.4.13 <0.7.7;

import "../interfaces/IERC20.sol";

// Placeholder Treasury to mimic structure of mainnet protocol on testnet
// Only needs to hold a TestDAI balance and give infinite allowance to Sports Book

contract TreasuryPlaceholder{
    constructor(address _sportsBook,address _testDAI){
        IERC20(_testDAI).approve(_sportsBook,uint(-1));
    }
}