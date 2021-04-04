pragma solidity ^0.5.0;

import 'https://github.com/aave/flashloan-box/blob/master/contracts/aave/ILendingPoolAddressesProvider.sol';
import 'https://github.com/aave/flashloan-box/blob/master/contracts/aave/ILendingPool.sol';
import 'https://github.com/aave/flashloan-box/blob/master/contracts/aave/FlashLoanReceiverBase.sol';

contract PoolBalancer is FlashLoanReceiverBase {
    ILendingPoolAddressesProvider provider;
    address dai;
    
    constructor(address _provider, address _dai) FlashLoanReceiverBase(_provider) public {
        provider = ILendingPoolAddressesProvider(_provider);
        dai = _dai;
    }
     
    function startLoan(uint amount, bytes calldata _params) external {
        ILendingPool pool = proivder.getLendingPool();
        ILendingPool.flashLoan(address(this), dai, amount, _params);
    }
    
    function executeOperation(address _reserve, uint _amount, uint _fee, bytes memory _params) external {
        // Do operations here, swap and what not
        
        transferFundsBackToPoolInternal(_reserve, amount+fee);
    }
}