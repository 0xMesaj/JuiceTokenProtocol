// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

/*

    Bridge to XDAI

*/

contract BridgeXDAI {
    using SafeMath for uint256;
    IERC20 JCE;
    IWDAI wdai;
    IERC20 dai;
    IUniswapV2Router02 immutable router;
    IUniswapV2Factory immutable factory;
    address immutable pair;
    
    constructor( IERC20 _JCE, IWDAI _wdai, IUniswapV2Router02 _uniswapV2Router) {
        JCE = _JCE;
        wdai = _wdai;
        dai = wdai.wrappedToken();
        router = _uniswapV2Router;
        factory = IUniswapV2Factory(_uniswapV2Router.factory());
        pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(address(JCE), address(wdai));

        wdai.approve(address(_uniswapV2Router),uint(-1));
        dai.approve(address(wdai),uint(-1));
        wdai.approve(address(wdai),uint(-1));
    }

}