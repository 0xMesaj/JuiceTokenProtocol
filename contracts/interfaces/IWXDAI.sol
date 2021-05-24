// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
import "./IERC206.sol";
import "./IWrappedERC20Events6.sol";

interface IWXDAI is IERC20,IWrappedERC20Events{    
    function deposit() external payable;
    function withdraw(uint256 _amount) external;
    
}
