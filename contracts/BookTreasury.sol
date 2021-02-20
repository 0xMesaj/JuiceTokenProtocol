pragma solidity ^0.7.0;

import "./SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWDAI.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./interfaces/IBookToken.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";
import 'hardhat/console.sol';

contract BookTreasury {
    using SafeERC20 for IERC20;

    mapping(address => bool) public strategies;
    mapping(address => bool) public treasurers;

    address mesaj;
    IBookToken BOOK;
    IERC20 DAI;
    IWDAI WDAI;
    IUniswapV2Factory factory;
    IUniswapV2Router02 router;
    ILockedLiqCalculator BookLiqCalculator;

    modifier isTreasurer(){
        require (treasurers[msg.sender], "Treasurers only");
        _;
    }

    function setWard(address appointee) public isTreasurer(){
        require(!treasurers[appointee], "Appointee is already treasurer.");
        treasurers[appointee] = true;
    }

    function removeWard(address shame) public isTreasurer(){
        require(mesaj != shame, "Et tu, Brute ?");
        treasurers[shame] = false;
    }
    
    constructor( IWDAI _wdai, IBookToken _BOOK, ILockedLiqCalculator _BookLiqCalculator, IUniswapV2Factory _factory, IUniswapV2Router02 _router) {
        factory = _factory;
        router = _router;
        BookLiqCalculator = _BookLiqCalculator;
        BOOK = _BOOK;
        WDAI = _wdai;
        DAI = WDAI.wrappedToken();
        mesaj = msg.sender;

        treasurers[mesaj] = true;
        WDAI.approve(address(router),uint(-1));
    }
    
    receive() external payable { }

    function addStrategy(address strategy) public isTreasurer(){
        require(!strategies[strategy], 'Specified address is already a strategy');
        strategies[strategy] = true;
        DAI.approve(strategy,uint(-1));
    }

    function numberGoUp(uint _amt) external isTreasurer(){
        WDAI.deposit(_amt);

        address[] memory path = new address[](2);
        path[0] = address(WDAI);
        path[1] = address(BOOK);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(WDAI.balanceOf(address(this)), 0, path, address(this), 2000000000000000000000);
        BOOK.burn(BOOK.balanceOf(address(this)));
    }
}