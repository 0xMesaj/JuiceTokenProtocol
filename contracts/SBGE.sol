pragma solidity ^0.7.0;

import 'hardhat/console.sol';
import './BookToken.sol';
import './SafeMath.sol';
import './TransferPortal.sol';
import './WDAI.sol';
import './interfaces/IBookLiquidity.sol';
import './interfaces/IBookTokenDistribution.sol';
import './interfaces/IERC20.sol';
import './interfaces/IBookTreasury.sol';
import './uniswap/IUniswapV2Pair.sol';
import './uniswap/IUniswapV2Factory.sol';
import './uniswap/libraries/TransferHelper.sol';
import "./uniswap/IUniswapV2Router02.sol";
import './uniswap/libraries/UniswapV2Library.sol';

contract SBGE {
    using SafeMath for uint256;
    
    mapping (address => uint256) public daiContribution;

    event Contribution(uint256 DAIamt, address from);

    uint256 public totalDAIContribution = 0;

    address[] public contributors;
    bool public isActive; 
    uint256 refundsAllowedUntil;
    address public owner;
    address public DAI;
    address public WETH;
    address public uniswapFactory;
    address public sushiswapFactory;
    bool public distributionComplete;
    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;
    BookToken immutable BOOK;
    WDAI immutable wdai;
    IERC20 immutable dai;
    IBookTreasury immutable treasury;

    IUniswapV2Pair BOOKwdai;
    IERC20 book_lpToken;


    uint256 public totalDAICollected;
    uint256 public totalBOOKBought;
    uint256 public totalBOOKwdai;
    uint256 public totalDAIwdai;
    uint256 recoveryDate = block.timestamp + 2592000; // 1 Month


    // Scaled By a Factor of 100, 10000 = 100%
    uint16 constant public poolPercent = 8000; // BOOK-wDAI Liquidity Pool
    uint16 constant public daiPoolPercent = 600; // DAI-wDAI Liquidity Pool
    uint16 constant public buyPercent = 400; // Used to execute initial purchase of BOOK token from LP for contributors
    uint16 constant public development = 500; // Developemt/Project Fund
    uint16 constant public devPayment = 500; // Payment

    mapping (address => uint256) public tokenReserves;

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }

    modifier active(){
        require(isActive, "Sports Book Generation Event is not active");
        _;
    }

    constructor(BookToken _BOOK, IUniswapV2Router02 _uniswapV2Router, WDAI _wdai, IBookTreasury _treasury, address _WETH){
        require (address(_BOOK) != address(0));
        require (address(_treasury) != address(0));

        BOOK = _BOOK;
        // DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;   //REAL WETH ADDR
        WETH = _WETH; // FAKE WETH ADDR
        // uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        // sushiswapFactory = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
        owner = msg.sender;

        uniswapV2Router = _uniswapV2Router;
        wdai = _wdai;
        treasury = _treasury;

        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
        dai = _wdai.wrappedToken();

        _wdai.wrappedToken().approve(address(_wdai),uint(-1));
        _wdai.approve(address(_uniswapV2Router), uint256(-1));
        _wdai.wrappedToken().approve(address(_uniswapV2Router), uint256(-1));
        _BOOK.approve(address(_uniswapV2Router), uint256(-1));
    }

    function activate() public ownerOnly(){
        require (!isActive && contributors.length == 0 && block.timestamp >= refundsAllowedUntil, "Already activated");     
        require (BOOK.balanceOf(address(this)) == BOOK.totalSupply(), "Missing supply");

        isActive = true;
    }

    function complete() public ownerOnly() active(){
        require (block.timestamp >= refundsAllowedUntil, "Refund period is still active");
        isActive = false;
        if (totalDAIContribution == 0) { return; }
        distribute();
    }

    function allowRefunds() public ownerOnly() active(){
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    function contributeDAI( uint256 _amount ) external payable active(){
        require(_amount > 0, "Contribution amount must be greater than 0");
        uint256 oldContribution = daiContribution[msg.sender];
        if (oldContribution == 0) {
            contributors.push(msg.sender);
        }
        dai.transferFrom(msg.sender, address(this), _amount);
        totalDAIContribution += _amount;
        daiContribution[msg.sender] += _amount;
        emit Contribution(_amount, msg.sender);
    }

    function contributeToken(address _token, uint256 _amount) external payable active(){
        require(_amount > 0, "Contribution amount must be greater than 0");
        uint256 oldContribution = daiContribution[msg.sender];
        uint256 newContribution = oldContribution + msg.value;
        if (oldContribution == 0 ) {
            contributors.push(msg.sender);
        }

        address token0;

        try IUniswapV2Pair(_token).token0() { token0 = IUniswapV2Pair(_token).token0(); } catch { }

        //UNI or SUSHI LP Token
        if(token0 != address(0)) {
            address token1 = IUniswapV2Pair(_token).token1();
            // console.log("token1=%s",token1);
            // console.log("token0=%s",token0);
            console.log("factory=%s",address(uniswapV2Factory));
            bool isUniLP = IUniswapV2Factory(uniswapV2Factory).getPair(token1,token0) !=  address(0);
            // bool isSushiLP = IUniswapV2Factory(sushiswapFactory).getPair(token0,token1) !=  address(0);
            bool isSushiLP = false;

            if(!isUniLP && !isSushiLP) { revert("LGE : LP Token type not accepted"); } // reverts here
            TransferHelper.safeTransferFrom(_token, msg.sender, _token, _amount);
            uint256 balanceToken0Before = IERC20(token0).balanceOf(address(this));
            uint256 balanceToken1Before = IERC20(token1).balanceOf(address(this));
            IUniswapV2Pair(_token).burn(address(this));
            uint256 balanceToken0After = IERC20(token0).balanceOf(address(this));
            uint256 balanceToken1After = IERC20(token1).balanceOf(address(this));

            uint256 amountOutToken0 = token0 == address(dai) ? 
                balanceToken0After.sub(balanceToken0Before)
                : sellTokenForDAI(token0, balanceToken0After.sub(balanceToken0Before), false);

            uint256 amountOutToken1 = token1 == address(dai) ? 
                balanceToken1After.sub(balanceToken1Before)
                : sellTokenForDAI(token1, balanceToken1After.sub(balanceToken1Before), false);

            uint256 balanceDAINew = IERC20(dai).balanceOf(address(this));

            uint256 reserveDAI = tokenReserves[address(dai)];

            require(balanceDAINew > reserveDAI, "No good");
            uint256 totalDAIAdded = amountOutToken0.add(amountOutToken1);
            require(tokenReserves[address(dai)].add(totalDAIAdded) <= balanceDAINew, "Too small... ;)");
            tokenReserves[address(dai)] = balanceDAINew;
           
            daiContribution[msg.sender] = daiContribution[msg.sender].add(totalDAIAdded);

            emit Contribution(totalDAIAdded, msg.sender);
            return;
        }//If token is not DAI then we sell it for DAI
        else if(_token != address(dai)){ 
            uint256 amountOut = sellTokenForDAI(_token, _amount, true);
            uint256 balanceDAINew = IERC20(dai).balanceOf(address(this));
            uint256 reserveDAI = tokenReserves[address(dai)];
            require(balanceDAINew > reserveDAI, "No good");
            require(reserveDAI.add(amountOut) <= balanceDAINew, "Too small... ;)");
            tokenReserves[WETH] = balanceDAINew;
            totalDAIContribution += amountOut;
            daiContribution[msg.sender] += amountOut;
        }
    }

    function claim() public{
        uint256 amount = daiContribution[msg.sender];
        require (amount > 0, "Nothing to claim");
        daiContribution[msg.sender] = 0;
        if (refundsAllowedUntil > block.timestamp) {
            (bool success,) = msg.sender.call{ value: amount }("");
            require (success, "Transfer failed");
        }
        else {
            _claim(msg.sender, amount);
        }
    }

   

    function sellTokenForDAI(address _token, uint256 _amount, bool _from) internal returns (uint256 daiAmount){
        address pairWithDAI = IUniswapV2Factory(uniswapV2Factory).getPair(_token, address(dai));
        require(pairWithDAI != address(0), "Unsellable Token Contributed. We no want your shitcoin");

        IERC20 token = IERC20(_token);
        IUniswapV2Pair pair = IUniswapV2Pair(pairWithDAI); 

        uint256 DAIReservePresale = token.balanceOf(pairWithDAI);
        if(_from) {
            TransferHelper.safeTransferFrom(_token, msg.sender, pairWithDAI, _amount); // re
        } else {
            TransferHelper.safeTransfer(_token, pairWithDAI, _amount);
        }
        uint256 DAIReservePostsale = token.balanceOf(pairWithDAI);
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        uint256 delta = DAIReservePostsale.sub(DAIReservePresale, "Subtraction is hard");

        if(pair.token0() == _token) {                  
            daiAmount = getAmountOut(delta, reserve0, reserve1);
            require(daiAmount < reserve1.mul(30).div(100), "Too much slippage in selling");
            pair.swap(0, daiAmount, address(this), "");
        } else {
            daiAmount = getAmountOut(delta, reserve1, reserve0);
            pair.swap(daiAmount, 0, address(this), "");
            require(daiAmount < reserve0.mul(30).div(100), "Too much slippage in selling");
        }
    }
    
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    receive() external payable active(){
        require(msg.value > 0, 'Value must me greater than 0');
        uint256 oldContribution = daiContribution[msg.sender];
        if ( oldContribution == 0 ) {
            contributors.push(msg.sender);
        }
        uint256 oldBalance = weth.balanceOf(address(this));
        weth.deposit(msg.value);
        uint256 newBalance = weth.balanceOf(address(this));
        require(newBalance > oldBalance, 'No wETH received from wrap');

        uint256 wETHamt = newBalance.sub(oldBalance);
        uint256 amountOut = sellTokenForDAI(weth, wETHamt, true);

        require(amountOut > 0, 'No DAI received from sale');
        daiContribution[msg.sender] += amountOut;
    }

    function setupBOOKwdai() public{
        BOOKwdai = IUniswapV2Pair(uniswapV2Factory.getPair(address(wdai), address(BOOK)));
        if (address(BOOKwdai) == address(0)) {
            BOOKwdai = IUniswapV2Pair(uniswapV2Factory.createPair(address(wdai), address(BOOK)));
            require (address(BOOKwdai) != address(0));
        }
    }

    function preBuyForGroup(uint256 amount) internal {      
        address[] memory path = new address[](2);
        path[0] = address(wdai);
        path[1] = address(BOOK);
        uint256 wrapAmount = amount.mul(buyPercent).div(10000);
        wdai.deposit(wrapAmount);
        uint256 buyAmount = wdai.balanceOf(address(this));
        uint256[] memory amountsBOOK = uniswapV2Router.swapExactTokensForTokens(buyAmount, 0, path, address(this), block.timestamp);

    }

    function distribute() internal {
        require (!distributionComplete, "Distribution complete");
        uint256 totalDAI = totalDAIContribution;
        require (totalDAI > 0, "Sad...");
        distributionComplete = true;
        totalDAICollected = totalDAI;

        TransferPortal portal = TransferPortal(address(BOOK.transferPortal()));
        portal.setUnrestricted(true);

        createBOOKwdaiLiquidity(totalDAI);
        createDAILiquidity(totalDAI);
        preBuyForGroup(totalDAI);

        dai.transfer(owner, dai.balanceOf(address(this)));

  
        portal.setUnrestricted(false);
    }

    function createDAILiquidity(uint256 totalDAI) internal {
        wdai.deposit(totalDAI.mul(daiPoolPercent).div(20000));
        
        //Deposit wDAI/DAI at 1:1 ratio
        (,,totalDAIwdai) = uniswapV2Router.addLiquidity(address(wdai), address(dai), wdai.balanceOf(address(this)), wdai.balanceOf(address(this)), 0, 0, address(this), block.timestamp);
        book_lpToken = IERC20(uniswapV2Factory.getPair(address(wdai), address(dai)));

    }

    function createBOOKwdaiLiquidity(uint256 totalDAI) internal{
        // Create WDAI/BOOK Liquidity Pool 
        wdai.deposit(totalDAI.mul(poolPercent).div(10000));

        (,,totalBOOKwdai) = uniswapV2Router.addLiquidity(address(wdai), address(BOOK), wdai.balanceOf(address(this)), BOOK.totalSupply(), 0, 0, address(this), block.timestamp);

    }

     function retrieveDAI() internal{
        wdai.fund(address(this));
        wdai.withdraw(wdai.balanceOf(address(this)));
    }

    function _claim(address _to, uint256 _contribution) internal {
        uint256 totalDAI = totalDAICollected;

        // Send Book/wDAI liquidity tokens
        uint256 share = _contribution.mul(totalBOOKwdai) / totalDAI;        
        if (share > book_lpToken.balanceOf(address(this))) {
            share = book_lpToken.balanceOf(address(this));
        }
        book_lpToken.transfer(_to, share);  

        // Send BOOK
        TransferPortal portal = TransferPortal(address(BOOK.transferPortal()));
        // portal.setUnrestricted(true);

        share = _contribution.mul(totalBOOKBought) / totalDAI;
        if (share > BOOK.balanceOf(address(this))) {
            share = BOOK.balanceOf(address(this));
        }
        BOOK.transfer(_to, share);

        portal.setUnrestricted(false);
    }

    
    
}