pragma solidity ^0.7.0;

import "./SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWDAI.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";
import './uniswap/libraries/TransferHelper.sol';
import './uniswap/IUniswapV2Pair.sol';
import './SafeMath.sol';

/*

 Convenience contract for JBT Protocol. Allows for purchase of  JBT without wDAI, and sale of JBT directly to other token
 in single tx...
 - Buys first convert purchasing token to DAI, then wrap to wDAI and purchase JBT, 
 - Sells first will sell JBT for wDAI then unwrap wDAI to DAI

*/

contract JuiceBookSwap {
    using SafeMath for uint256;
    IERC20 JBT;
    IWDAI wdai;
    IERC20 dai;
    IUniswapV2Router02 immutable router;
    IUniswapV2Factory immutable factory;
    address immutable pair;
    
    constructor( IERC20 _JBT, IWDAI _wdai, IUniswapV2Router02 _uniswapV2Router) {
        JBT = _JBT;
        wdai = _wdai;
        dai = wdai.wrappedToken();
        router = _uniswapV2Router;
        factory = IUniswapV2Factory(_uniswapV2Router.factory());
        pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(address(JBT), address(wdai));

        wdai.approve(address(_uniswapV2Router),uint(-1));
        dai.approve(address(wdai),uint(-1));
        wdai.approve(address(wdai),uint(-1));
    }

    function buyJBTwithDAI(uint256 amt) public {
        uint256 pre_wdaiBalance = wdai.balanceOf(address(this));
        dai.transferFrom(msg.sender, address(this), amt);
        wdai.deposit(amt);
        uint256 post_wdaiBalance = wdai.balanceOf(address(this));
        require(post_wdaiBalance == (amt.add(pre_wdaiBalance)), "Error: Wrap");

        uint256 pre_JBTBalance = JBT.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(wdai);
        path[1] = address(JBT);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amt, 0, path, address(this), block.timestamp);
        uint256 post_JBTBalance = JBT.balanceOf(address(this));
        require(post_JBTBalance > pre_JBTBalance, "Error: Swap");
        uint256 JBTAmt = post_JBTBalance.sub(pre_JBTBalance);
        JBT.transfer(msg.sender, JBTAmt);
    }

    function sellJBTforDAI(uint256 amt) public {
        JBT.transferFrom(msg.sender, address(this), amt);
        address[] memory path = new address[](2);
        path[0] = address(JBT);
        path[1] = address(wdai);
        JBT.approve(address(router),uint(-1));
        uint256 sellAmt = JBT.balanceOf(address(this));

        uint256 pre_wdaiBalance = wdai.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(sellAmt, 0, path, address(this), block.timestamp);
        uint256 post_wdaiBalance = wdai.balanceOf(address(this));
        require(post_wdaiBalance > pre_wdaiBalance, "Error: Swap");

        uint256 pre_daiBalance = dai.balanceOf(address(this));
        wdai.withdraw(post_wdaiBalance.sub(pre_wdaiBalance));

        uint256 post_daiBalance = dai.balanceOf(address(this));
        require(post_daiBalance > pre_daiBalance, "Error: Unwrap");
        require(post_daiBalance.sub(pre_daiBalance) == (post_wdaiBalance.sub(pre_wdaiBalance)), "Error: Check");
        uint256 daiAmt = post_daiBalance.sub(pre_daiBalance);
        dai.transfer(msg.sender, daiAmt);
    }
}