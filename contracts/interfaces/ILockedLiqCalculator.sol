pragma solidity ^0.7.0;

import "./IERC20.sol";

interface ILockedLiqCalculator{
    function calculateLockedwDAI(IERC20 wrappedToken, address backingToken) external view returns (uint256);
    function simulateWDAISell(IERC20 wrappedToken, address backingToken) external view returns (uint256);
}