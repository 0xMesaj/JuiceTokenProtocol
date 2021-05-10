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

    function simulateSell(IERC20 wrappedToken, address backingToken) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(JCE), backingToken);
        uint256 freeJCE = JCE.totalSupply().sub(JCE.balanceOf(pair));

        uint256 sellAllProceeds = 0;
        if (freeJCE > 0) {
            address[] memory path = new address[](2);
            path[0] = address(JCE);
            path[1] = backingToken;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), freeJCE, path);
            sellAllProceeds = amountsOut[1];
        }
 
        return sellAllProceeds;
    }

    function calculateLockedwDAI(IERC20 wrappedToken, address backingToken) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(JCE), backingToken);
        uint256 freeJCE = JCE.totalSupply().sub(JCE.balanceOf(pair));

        uint256 sellAllProceeds = 0;
        if (freeJCE > 0) {
            address[] memory path = new address[](2);
            path[0] = address(JCE);
            path[1] = backingToken;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), freeJCE, path);
            sellAllProceeds = amountsOut[1];
        }
       
        uint256 backingInPool = IERC20(backingToken).balanceOf(pair);
  
        if (backingInPool <= sellAllProceeds) { return 0; }
        uint256 excessInPool = backingInPool - sellAllProceeds;

        uint256 requiredBacking = IERC20(backingToken).totalSupply().sub(excessInPool);
        
        uint256 currentBacking = wrappedToken.balanceOf(address(backingToken));
        if (requiredBacking >= currentBacking) { return 0; }

        return currentBacking - requiredBacking;
    }

    
}