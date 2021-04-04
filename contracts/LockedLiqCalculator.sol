pragma solidity ^0.7.0;

import "./interfaces/ILockedLiqCalculator.sol";
import "./BookToken.sol";
import "./SafeMath.sol";
import "./uniswap/libraries/UniswapV2Library.sol";
import "./uniswap/IUniswapV2Factory.sol";
import './interfaces/IERC20.sol';

contract LockedLiqCalculator is ILockedLiqCalculator{
    using SafeMath for uint256;

    BookToken immutable BOOK;
    IUniswapV2Factory immutable uniswapV2Factory;

    constructor(BookToken _BOOK, IUniswapV2Factory _uniswapV2Factory){
        BOOK = _BOOK;
        uniswapV2Factory = _uniswapV2Factory;
    }

    function calculateLockedwDAI(IERC20 wrappedToken, address backingToken) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(BOOK), backingToken);
        uint256 freeBOOK = BOOK.totalSupply().sub(BOOK.balanceOf(pair));

        uint256 sellAllProceeds = 0;
        if (freeBOOK > 0) {
            address[] memory path = new address[](2);
            path[0] = address(BOOK);
            path[1] = backingToken;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), freeBOOK, path);
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

    function simulateSell(IERC20 wrappedToken, address backingToken) public override view returns (uint256){
        address pair = UniswapV2Library.pairFor(address(uniswapV2Factory), address(BOOK), backingToken);
        uint256 freeBOOK = BOOK.totalSupply().sub(BOOK.balanceOf(pair));

        uint256 sellAllProceeds = 0;
        if (freeBOOK > 0) {
            address[] memory path = new address[](2);
            path[0] = address(BOOK);
            path[1] = backingToken;
            uint256[] memory amountsOut = UniswapV2Library.getAmountsOut(address(uniswapV2Factory), freeBOOK, path);
            sellAllProceeds = amountsOut[1];
        }
       
        uint256 backingInPool = IERC20(backingToken).balanceOf(pair);
  
        if (backingInPool <= sellAllProceeds) { return 0; }
 
        return sellAllProceeds;
    }
}