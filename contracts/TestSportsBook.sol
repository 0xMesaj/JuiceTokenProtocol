pragma solidity ^0.7.0;

import 'hardhat/console.sol';
import './interfaces/IERC20.sol';

contract TestSportsBook  {
    IERC20 dai;
    address treasury;

    constructor (IERC20 _dai) payable{
        dai = _dai;
    }

    function bet(uint256 _amount, bool _win) external {
        if(_win){
            IERC20(dai).transferFrom(treasury, msg.sender, _amount);
        }
        else{        
            IERC20(dai).transferFrom(msg.sender, treasury, _amount);
        }
    }

    function setTreasury(address _treasury) external{
        treasury = _treasury;
    }


    receive() external payable {

    }

}