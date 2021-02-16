pragma solidity ^0.7.0;

import "../ERC20.sol";

contract ERC20Test is ERC20("Test", "TST") 
{ 
    constructor()
    {
        _mint(msg.sender, 10000 ether);
    }
}