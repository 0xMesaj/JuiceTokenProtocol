pragma solidity ^0.6.12;

import "../ERC206.sol";

contract TestToken is  ERC20 {
    constructor() public ERC20("DAI", "DAI") { }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}