pragma solidity ^0.7.0;

import './SafeMath.sol';
import './TransferPortal.sol';
import './WDAI.sol';
import './interfaces/IJuiceToken.sol';
import './interfaces/IBookLiquidity.sol';
import './interfaces/IBookTokenDistribution.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/IJuiceBookTreasury.sol';
import './uniswap/IUniswapV2Pair.sol';
import './uniswap/IUniswapV2Factory.sol';
import './uniswap/libraries/TransferHelper.sol';
import "./uniswap/IUniswapV2Router02.sol";
import './uniswap/libraries/UniswapV2Library.sol';

/*
    Sports Book Generation Contract - Once activated this contract will gather liquidity from
    contributors. Once completed this contract will initialize the BOOK-wDAI and wDAI-DAI UNI LPs.
    This contract will then use a portion of the liquidity generated to market buy BOOK
    Token to be distributed to the contributors, which will be at the floor price of BOOK. This is to prevent 
    greedy bots and instead SBGE contributors are in at the floor price.

    This contract accepts many different forms of contributions: DAI, ETH, Uniswap or Sushiswap LP
    Tokens, or any token that this contract can be flash swapped for DAI on Uniswap. All contributions will
    be denominated in DAI. LP tokens are unwrapped and the underlying tokens are sold for DAI.
*/

contract SBGE {
    using SafeMath for uint256;
    
    mapping (address => uint256) public daiContribution;

    event Contribution(uint256 DAIamt, address from);

    uint256 public totalDAIContribution = 0;
    address[] public contributors;
    bool public isActive;
    uint256 refundsAllowedUntil;
    address public mesaj;
    address public DAI;
    IWETH public WETH;
    address public uniswapFactory;
    address public sushiswapFactory;
    bool public distributionComplete;

    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;

    IJuiceToken immutable JCE;
    WDAI immutable wdai;
    IERC20 immutable dai;
    IJuiceBookTreasury immutable treasury;

    IUniswapV2Pair JCEwdai;
    IERC20 lpToken;

    uint256 public totalDAICollected;
    uint256 public totalJCEBought;
    uint256 public totalJCEwdai;
    uint256 public totalDAIwdai;

    // Scaled By a Factor of 100: 10000 = 100%
    uint16 constant public poolPercent = 8000; // JCE-wDAI Liquidity Pool
    uint16 constant public daiPoolPercent = 600; // DAI-wDAI Liquidity Pool
    uint16 constant public buyPercent = 400; // Used to execute initial purchase of JCE from LP for contributors
    uint16 constant public development = 500; // Developemt/Project Fund
    uint16 constant public devPayment = 500; // Payment

    modifier isMesaj(){
        require (msg.sender == mesaj, "No");
        _;
    }

    modifier active(){
        require(isActive, "Sports Book Generation Event is not active");
        _;
    }

    constructor(IJuiceToken _JCE, IUniswapV2Router02 _uniswapV2Router, WDAI _wdai, IJuiceBookTreasury _treasury, IWETH _WETH){
        require (address(_JCE) != address(0x0));
        require (address(_treasury) != address(0x0));

        JCE = _JCE;
        // DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;   //REAL WETH ADDR
        WETH = _WETH; // FAKE WETH ADDR
        // uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        // sushiswapFactory = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
        mesaj = msg.sender;

        uniswapV2Router = _uniswapV2Router;
        wdai = _wdai;
        treasury = _treasury;

        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
        dai = _wdai.wrappedToken();

        _wdai.wrappedToken().approve(address(_wdai),uint(-1));
        _wdai.approve(address(_uniswapV2Router), uint256(-1));
        _wdai.wrappedToken().approve(address(_uniswapV2Router), uint256(-1));
        _JCE.approve(address(_uniswapV2Router), uint256(-1));
        _WETH.approve(address(_uniswapV2Router), uint256(-1));
    }

    function activate() public isMesaj(){
        require (!isActive && contributors.length == 0 && block.timestamp >= refundsAllowedUntil, "Already activated");
        require (JCE.balanceOf(address(this)) == JCE.totalSupply(), "Total token supply required to activate SBGE");

        isActive = true;
    }

    function complete() public isMesaj() active(){
        require (block.timestamp >= refundsAllowedUntil, "Refund period active");
        require (totalDAIContribution > 0, "No liquidity generated");
        isActive = false;
        distribute();
    }

    // Trigger refund - This will make the completion function uncallable
    function allowRefunds() public isMesaj() active(){
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    /*
        External Functions for User Contribution
    */

    // DAI Contribution
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

    // ERC20 Token or Uni V2/Sushi LP Token Contribution
    function contributeToken(address _token, uint256 _amount) external payable active(){
        require(_amount > 0, "Contribution amount must be greater than 0");
        uint256 oldContribution = daiContribution[msg.sender];

        if (oldContribution == 0 ) {
            contributors.push(msg.sender);
        }

        address token0;

        try IUniswapV2Pair(_token).token0() { token0 = IUniswapV2Pair(_token).token0(); } catch { }

        //UNI or SUSHI LP Token
        if(token0 != address(0)) {
            address token1 = IUniswapV2Pair(_token).token1();

            bool isUniLP = IUniswapV2Factory(uniswapV2Factory).getPair(token0,token1) !=  address(0);
            bool isSushiLP = IUniswapV2Factory(sushiswapFactory).getPair(token0,token1) !=  address(0);
            // bool isSushiLP = false;

            if(!isUniLP && !isSushiLP) { revert("SBGE Error: LP Token Not Supported"); } // reverts here
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

            uint256 totalDAIAdded = amountOutToken0.add(amountOutToken1);

            totalDAIContribution = totalDAIContribution.add(totalDAIAdded);
            daiContribution[msg.sender] = daiContribution[msg.sender].add(totalDAIAdded);

            emit Contribution(totalDAIAdded, msg.sender);
            return;
        }//If token is not DAI then we sell it for DAI
        else if(_token != address(dai)){ 
            uint256 balanceDAIOld = IERC20(dai).balanceOf(address(this));
            uint256 amountOut = sellTokenForDAI(_token, _amount, true);
            uint256 balanceDAINew = IERC20(dai).balanceOf(address(this));
            require(balanceDAIOld < balanceDAINew, "DAI Received From Sale Insufficient");
            totalDAIContribution = totalDAIContribution.add(amountOut);
            daiContribution[msg.sender] = daiContribution[msg.sender].add(amountOut);
            emit Contribution(amountOut, msg.sender);
        }
        require(daiContribution[msg.sender] > oldContribution, "No new contribution added.");
    }

    //ETH contribution
    receive() external payable active(){
        require(msg.value > 0, 'Value must me greater than 0');
        uint256 oldContribution = daiContribution[msg.sender];
        if ( oldContribution == 0 ) {
            contributors.push(msg.sender);
        }
        uint256 oldBalance = WETH.balanceOf(address(this));
        WETH.deposit{value : msg.value}();
        uint256 newBalance = WETH.balanceOf(address(this));
        require(newBalance > oldBalance, 'No wETH received from wrap');

        uint256 wETHamt = newBalance.sub(oldBalance);
        uint256 amountOut = sellTokenForDAI(address(WETH), wETHamt, false);

        require(amountOut > 0, 'No DAI received from sale');
        daiContribution[msg.sender] += amountOut;
        emit Contribution(amountOut, msg.sender);
    }

    function claim() public{
        uint256 amount = daiContribution[msg.sender];
        require (amount > 0, "Nothing to claim");
        require(!isActive, "SBGE still active");
        daiContribution[msg.sender] = 0;

        /*
            If refund is active refund DAI contribution -
            else claim their LP and JCE token
        */
        if (refundsAllowedUntil > block.timestamp) {
            dai.transfer(msg.sender, amount);
        }
        else {
            _claim(msg.sender, amount);
        }
    }

    //Swap token to WETH then to DAI
    function sellTokenForDAI(address _token, uint256 _amount, bool _from) internal returns (uint256 daiAmount){
        address pairWithWETH = IUniswapV2Factory(uniswapV2Factory).getPair(_token, address(WETH));
        require(pairWithWETH != address(0x0), "Unsellable Token Contributed. We no want your shitcoin");
        
        IERC20 token = IERC20(_token);
        IUniswapV2Pair pair = IUniswapV2Pair(pairWithWETH); 

        uint256 tokenReservePresale = token.balanceOf(pairWithWETH);

        if(_from) {
            TransferHelper.safeTransferFrom(_token, msg.sender, pairWithWETH, _amount);
        } else {
            TransferHelper.safeTransfer(_token, pairWithWETH, _amount);
        }
        uint256 tokenReservePostsale = token.balanceOf(pairWithWETH);
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        uint256 preWETHBalance = WETH.balanceOf(address(this));

        uint256 delta = tokenReservePostsale.sub(tokenReservePresale, "Subtraction is hard");
        uint256 wethAMT;
        if(pair.token0() == _token) {              
            wethAMT = getAmountOut(delta, reserve0, reserve1);
            require(wethAMT < reserve1.mul(30).div(100), "Too much slippage in selling");
            pair.swap(0, wethAMT, address(this), "");
        } else {
            wethAMT = getAmountOut(delta, reserve1, reserve0);
            
            require(wethAMT < reserve0.mul(30).div(100), "Too much slippage in selling");
            pair.swap(wethAMT, 0, address(this), "");
        }
        uint256 postWETHBalance = WETH.balanceOf(address(this));
        uint256 WETHamt = preWETHBalance.sub(postWETHBalance);

        //SWAP WETH to DAI
        uint256 preDAIBalance = dai.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(dai);
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(WETHamt, 0, path, address(this), block.timestamp);
        uint256 postDAIBalance = dai.balanceOf(address(this));
        require(postDAIBalance > preDAIBalance, "Error: Swap");
        daiAmount = postDAIBalance.sub(preDAIBalance);
    }
    
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }


    function setupJCEwdai() public isMesaj() {
        JCEwdai = IUniswapV2Pair(uniswapV2Factory.getPair(address(wdai), address(JBT)));
        if (address(JCEwdai) == address(0)) {
            JCEwdai = IUniswapV2Pair(uniswapV2Factory.createPair(address(wdai), address(JBT)));
            require (address(JCEwdai) != address(0));
        }
    }

    function preBuyForGroup(uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = address(wdai);
        path[1] = address(JCE);
        uint256 wrapAmount = amount.mul(buyPercent).div(10000);
        wdai.deposit(wrapAmount);
        uint256 buyAmount = wdai.balanceOf(address(this));
        uint256[] memory amountsJCE = uniswapV2Router.swapExactTokensForTokens(buyAmount, 0, path, address(this), block.timestamp);

    }

    function distribute() internal {
        require (!distributionComplete, "Distribution complete");
        uint256 totalDAI = totalDAIContribution;
        
        require (totalDAI > 0, "No Liquidity Generated");
        distributionComplete = true;
        totalDAICollected = totalDAI;

        TransferPortal portal = TransferPortal(address(JCE.transferPortal()));
        portal.setFreeTransfers(true);

        createJCEwdaiLiquidity(totalDAI);
        createDAILiquidity(totalDAI);
        preBuyForGroup(totalDAI);

        dai.transfer(mesaj, dai.balanceOf(address(this))); //Dev fund/payment
  
        portal.setFreeTransfers(false);
    }

    function createDAILiquidity(uint256 totalDAI) internal {
        //Wrap half allocated DAI liquidity into wDAI
        wdai.deposit(totalDAI.mul(daiPoolPercent).div(20000));
        
        //Deposit wDAI/DAI at 1:1 ratio - use same wDAI balance as parameter to ensure 1:1
        (,,totalDAIwdai) = uniswapV2Router.addLiquidity(address(wdai), address(dai), wdai.balanceOf(address(this)), wdai.balanceOf(address(this)), 0, 0, address(this), block.timestamp);
    }

    function createJCEwdaiLiquidity(uint256 totalDAI) internal{
        // Create WDAI/JCE Liquidity Pool 
        wdai.deposit(totalDAI.mul(poolPercent).div(10000));

        (,,totalJCEwdai) = uniswapV2Router.addLiquidity(address(wdai), address(JCE), wdai.balanceOf(address(this)), JCE.totalSupply(), 0, 0, address(this), block.timestamp);
        lpToken = IERC20(uniswapV2Factory.getPair(address(wdai), address(JCE)));
    }

    function _claim(address _to, uint256 _contribution) internal {
        uint256 totalDAI = totalDAICollected;

        // Send JCE/wDAI liquidity tokens
        uint256 share = _contribution.mul(totalJCEwdai) / totalDAI;
        if (share > lpToken.balanceOf(address(this))) {
            share = lpToken.balanceOf(address(this));
        }
        lpToken.transfer(_to, share);  

        // Send JCE
        TransferPortal portal = TransferPortal(address(JCE.transferPortal()));
        portal.setFreeTransfers(true);

        share = _contribution.mul(totalJCEBought) / totalDAI;
        if (share > JCE.balanceOf(address(this))) {
            share = JCE.balanceOf(address(this));
        }
        JCE.transfer(_to, share);

        portal.setFreeTransfers(false);
    }

}