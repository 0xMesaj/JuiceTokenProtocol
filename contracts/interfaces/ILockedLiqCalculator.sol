pragma solidity ^0.7.0;

import "./IERC20.sol";

interface ILockedLiqCalculator{
    function calculateSubFloor(IERC20 wrappedToken, address backingToken) external view returns (uint256);
}