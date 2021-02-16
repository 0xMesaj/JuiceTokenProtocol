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

    address owner;

    address pair;
    mapping(address => bool) public strategies;
    mapping(address => bool) public treasurers;

    IBookToken BOOK;
    IERC20 DAI;
    IWDAI WDAI;
    IUniswapV2Factory factory;
    IUniswapV2Router02 router;
    ILockedLiqCalculator BookLiqCalculator;

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }
    
    constructor(address SportsBook,IERC20 _DAI, IBookToken _BOOK, ILockedLiqCalculator _BookLiqCalculator, IUniswapV2Factory _factory,IUniswapV2Router02 _router) {
        factory = _factory;
        router = _router;
        BookLiqCalculator = _BookLiqCalculator;
        BOOK = _BOOK;
        DAI = _DAI;
        owner = msg.sender;
        strategies[SportsBook] = true;
        treasurers[msg.sender] = true;
        DAI.approve(SportsBook,uint(-1));
    }
    
    receive() external payable { }

    function sendEther(address payable _to, uint256 _amount) public ownerOnly(){
        (bool success,) = _to.call{ value: _amount }("");
        require (success, "Transfer failed");
    }

    function sendToken(IERC20 _token, address _to, uint256 _amount) public {
        require(treasurers[msg.sender], "Only Treasurers have access");
        require(strategies[_to], "Recipient is not an approved strategy");
        _token.safeTransfer(_to, _amount);
    }

    function setWDAI(IWDAI _WDAI) external ownerOnly(){
        WDAI = _WDAI;
        WDAI.approve(address(router),uint(-1));
        DAI.approve(address(WDAI),uint(-1));
    }

    function getPair() external ownerOnly(){
        pair = factory.getPair(address(BOOK), address(WDAI));
    }

    function numberGoUp(uint _amt) external ownerOnly(){
        WDAI.deposit(_amt);

        address[] memory path = new address[](2);
        path[0] = address(WDAI);
        path[1] = address(BOOK);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(WDAI.balanceOf(address(this)), 0, path, address(this), 2000000000000000000000);
        // console.log("Locked Liq res=%s",BookLiqCalculator.calculateSubFloor(DAI,address(WDAI)));
        console.log("Burning %s Book Token", BOOK.balanceOf(address(this)) );
        BOOK.burn(BOOK.balanceOf(address(this)));
        // console.log("Post Book Burn Locked Liq res=%s",BookLiqCalculator.calculateSubFloor(DAI,address(WDAI)));
    }
}