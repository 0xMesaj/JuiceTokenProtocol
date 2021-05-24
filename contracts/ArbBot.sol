// //SPDX-License-Identifier: MIT
// pragma solidity ^0.5.0;
// pragma experimental ABIEncoderV2;

// import "@studydefi/money-legos/dydx/contracts/DydxFlashloanBase.sol";
// import "@studydefi/money-legos/dydx/contracts/ICallee.sol";

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import './uniswap/IUniswapV2Pair.sol';
// import './uniswap/IUniswapV2Router02.sol';
// import './interfaces/IWDAI.sol';

// contract ArbBot is ICallee, DydxFlashloanBase {
//     address lp;
//     address mesaj;
//     IWDAI wDAI;

//     constructor(address _lp, IWDAI _wDAI){
//         mesaj = msg.sender;
//         lp = _lp;
//         wDAI = _wDAI;
//     }

//     function setLPAddress(address _lp){
//         require(msg.owner = mesaj, "Mesaj only");
//         lp = _lp;
//     }

//     struct MyCustomData {
//         address token;
//         uint256 repayAmount;
//     }

//     // This is the function that will be called postLoan
//     // i.e. Encode the logic to handle your flashloaned funds here
//     function callFunction(
//         address sender,
//         Account.Info memory account,
//         bytes memory data
//     ) public {
//         MyCustomData memory mcd = abi.decode(data, (MyCustomData));
//         uint256 balOfLoanedToken = IERC20(mcd.token).balanceOf(address(this));

//         // Note that you can ignore the line below
//         // if your dydx account (this contract in this case)
//         // has deposited at least ~2 Wei of assets into the account
//         // to balance out the collaterization ratio
//         require(
//             balOfLoanedToken >= mcd.repayAmount,
//             "Not enough funds to repay dydx loan!"
//         );

//         // TODO: Encode your logic here
//         // E.g. arbitrage, liquidate accounts, etc
//         // revert("Hello, you haven't encoded your logic");

//         //Reserve 0 is DAI reserve and Reserve 1 is wDAI reserve
//         (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(lp);

//         // wDAI above $1, wrap DAI->wDAI then swap wDAI for DAI
//         if(reserve0 > reserve1){
//             IWDAI(wDAI).deposit(balOfLoanedToken);
//             uint256 wDAIbal = IERC20(wDAI).balanceOf(address(this));
//             address[] memory path = new address[](2);
//             path[0] = address(wDAI);
//             path[1] = address(mcd.token);
//             uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(wDAIbal, 0, path, address(this), block.timestamp);
//         }
//         else{   //wDAI below $1, swap DAI for wDAI then unwrap wDAI->DAI
//             address[] memory path = new address[](2);
//             path[0] = address(mcd.token);
//             path[1] = address(wDAI);
//             uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(balOfLoanedToken, 0, path, address(this), block.timestamp);
//             uint256 wDAIBalance = wDAI.balanceOf(address(this));
//             IWDAI(wDAI).withdraw(wDAIBalance);
//         }
//     }

//     function initiateFlashLoan(address _solo, address _token, uint256 _amount)
//         external
//     {
//         ISoloMargin solo = ISoloMargin(_solo);

//         // Get marketId from token address
//         uint256 marketId = _getMarketIdFromTokenAddress(_solo, _token);

//         // Calculate repay amount (_amount + (2 wei))
//         // Approve transfer from
//         uint256 repayAmount = _getRepaymentAmountInternal(_amount);
//         IERC20(_token).approve(_solo, repayAmount);

//         // 1. Withdraw $
//         // 2. Call callFunction(...)
//         // 3. Deposit back $
//         Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

//         operations[0] = _getWithdrawAction(marketId, _amount);
//         operations[1] = _getCallAction(
//             // Encode MyCustomData for callFunction
//             abi.encode(MyCustomData({token: _token, repayAmount: repayAmount}))
//         );
//         operations[2] = _getDepositAction(marketId, repayAmount);

//         Account.Info[] memory accountInfos = new Account.Info[](1);
//         accountInfos[0] = _getAccountInfo();

//         solo.operate(accountInfos, operations);
//     }
// }