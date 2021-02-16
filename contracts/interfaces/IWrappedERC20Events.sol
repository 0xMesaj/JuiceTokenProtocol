pragma solidity ^0.7.0;

interface IWrappedERC20Events
{
    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
}
