// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./interfaces/ILockedLiqCalculator.sol";
import "./JuiceToken.sol";
import "./SafeMath.sol";
import "./uniswap/libraries/UniswapV2Library.sol";
import "./uniswap/IUniswapV2Factory.sol";
import './interfaces/IERC20.sol';

contract LockedLiqCalculator is ILockedLiqCalculator{
    using SafeMath for uint256;

    JuiceToken immutable JCE;
    IUniswapV2Factory immutable uniswapV2Factory;

    constructor(JuiceToken _JCE, IUniswapV2Factory _uniswapV2Factory){
        JCE = _JCE;
        uniswapV2Factory = _uniswapV2Factory;
    }

    // Returns wDAI amount that would be extracted from JCE-wDAI LP if 100% of circulating JCE was sold
    function simulateSell(address _wdai) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(JCE), _wdai);
        uint256 circJCE = JCE.totalSupply().sub(JCE.balanceOf(pair));

        uint256 potential = 0;
        if (circJCE > 0) {
            address[] memory path = new address[](2);
            path[0] = address(JCE);
            path[1] = _wdai;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), circJCE, path);
            potential = amountsOut[1];
        }
 
        return potential; // amount of wDAI that would be swapped out of JCE-wDAI LP if all circ JCE was sold into JCE-wDAI LP
    }

    function calculateLockedwDAI(IERC20 _dai, address _wdai) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(JCE), _wdai);
        uint256 circJCE = JCE.totalSupply().sub(JCE.balanceOf(pair));

        uint256 potential = 0;
        if (circJCE > 0) {
            address[] memory path = new address[](2);
            path[0] = address(JCE);
            path[1] = _wdai;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), circJCE, path);
            potential = amountsOut[1];  // amount of wDAI that would be swapped out of JCE-wDAI LP if all circ JCE was sold into JCE-wDAI LP
        }
       
        uint256 wDAIinPool = IERC20(_wdai).balanceOf(pair); //total wDAI in JCE-wDAI LP
  
        if (wDAIinPool <= potential) { return 0; }
        uint256 lockedWDAI = wDAIinPool - potential;    // amount of wDAI perm locked in JCE-wDAI LP

        uint256 requiredBacking = IERC20(_wdai).totalSupply().sub(lockedWDAI);  // total wDAI that could possbily be unwrapped into DAI
        
        uint256 currentBacking = _dai.balanceOf(address(_wdai));
        if (requiredBacking >= currentBacking) { return 0; }

        return currentBacking - requiredBacking;    // amount of DAI liquidity in wDAI contract that can be released to Juice Treasury
    }
}