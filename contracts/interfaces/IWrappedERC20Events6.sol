// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IWrappedERC20Events
{
    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
}
