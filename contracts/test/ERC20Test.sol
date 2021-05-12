pragma solidity ^0.6.12;

import "../ERC206.sol";

contract ERC20Test is ERC20("Test", "TST") 
{ 
    constructor() public
    {
        _mint(msg.sender, 100000000 ether);
    }
}