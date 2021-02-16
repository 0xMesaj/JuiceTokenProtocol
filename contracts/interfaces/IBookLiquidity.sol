pragma solidity ^0.7.0;

import "./IERC20.sol";
import "./IWrappedERC20Events.sol";

interface IBookLiquidity is IERC20, IWrappedERC20Events{
    function wrappedToken() external view returns (IERC20);
    function depositTokens(uint256 _amount) external;
    function withdrawTokens(uint256 _amount) external;
}