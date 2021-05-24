// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import './SafeMath.sol';
import './TransferPortal.sol';
import './WDAI.sol';
import './interfaces/IJuiceToken.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './uniswap/IUniswapV2Pair.sol';
import './uniswap/IUniswapV2Factory.sol';
import './uniswap/libraries/TransferHelper.sol';
import "./uniswap/IUniswapV2Router02.sol";
import './uniswap/libraries/UniswapV2Library.sol';

/*
    Sports Book Generation Event (SBGE) Contract - Once activated this contract will gather liquidity from
    contributors. Once completed this contract will initialize the JCE-wDAI and wDAI-DAI UNI LPs.
    This contract will then use a portion of the liquidity generated to market buy JCE
    Token to be distributed to the contributors, which will be at the floor price of JCE. This is to prevent 
    greedy bots and instead SBGE contributors are in at the floor price.

    This contract accepts many different forms of contributions: DAI, ETH,, or any token that this contract can be flash swapped
    for DAI on Uniswap. All contributions will be denominated in DAI. LP tokens are unwrapped and the underlying tokens are sold for DAI.
*/

contract SBGE {
    using SafeMath for uint256;
    
    mapping (address => uint256) public daiContribution;

    event NewContribution(uint256 DAIamt, address from);
    event Contribution(uint256 DAIamt, address from);

    uint256 public totalDAIContribution = 0; 
    uint256 refundsAllowedUntil;

    address[] public contributors;
    address public mesaj;
    bool public distributionComplete;
    bool public isActive;

    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;

    IJuiceToken immutable JCE;
    WDAI immutable wdai;
    IERC20 immutable dai;
    IWETH public WETH;
    address immutable treasury;

    IUniswapV2Pair JCEwdai;
    IERC20 lpToken;

    uint256 public totalDAICollected;
    uint256 public totalJCEBought;
    uint256 public totalJCEwdai;
    uint256 public totalDAIwdai;

    // Scaled By a Factor of 100: 10000 = 100%
    uint16 constant public poolPercent = 8000; // JCE-wDAI Liquidity Pool
    uint16 constant public daiPoolPercent = 600; // DAI-wDAI Liquidity Pool
    uint16 constant public buyPercent = 500; // Used to execute initial purchase of JCE from LP for contributors
    uint16 constant public development = 500; // Development/Project Fund
    uint16 constant public devPayment = 400; // Payment

    modifier isMesaj(){
        require (msg.sender == mesaj, "Mesaj Only");
        _;
    }

    modifier active(){
        require(isActive, "Sports Book Generation Event is not active");
        _;
    }
 
    constructor(IJuiceToken _JCE, WDAI _wdai, address _treasury, IWETH _WETH, IUniswapV2Router02 _router){
        require (address(_JCE) != address(0x0));
        require (_treasury != address(0x0));

        JCE = _JCE;
        WETH = _WETH;
        mesaj = msg.sender;
        uniswapV2Router = _router;
        wdai = _wdai;
        treasury = _treasury;

        uniswapV2Factory = IUniswapV2Factory(_router.factory());
        dai = _wdai.wrappedToken();

        _wdai.wrappedToken().approve(address(_wdai),uint(-1));
        _wdai.approve(address(_router), uint256(-1));
        _wdai.wrappedToken().approve(address(_router), uint256(-1));
        _JCE.approve(address(_router), uint256(-1));
        _WETH.approve(address(_router), uint256(-1));
    }

    function activate() public isMesaj(){
        require (!isActive && contributors.length == 0 && block.timestamp >= refundsAllowedUntil, "Already activated");
        require (JCE.balanceOf(address(this)) == JCE.totalSupply(), "Total Juice token supply required to activate SBGE");

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

        dai.transferFrom(msg.sender, address(this), _amount);
        totalDAIContribution = totalDAIContribution.add(_amount);
        daiContribution[msg.sender] = daiContribution[msg.sender].add(_amount);
        require(daiContribution[msg.sender] > oldContribution, "No new contribution added.");
        if (oldContribution == 0) {
            contributors.push(msg.sender);
            emit NewContribution(_amount, msg.sender);
        }else{
            emit Contribution(_amount, msg.sender);
        }
    }

    // ERC20 Token Contribution
    function contributeToken(address _token, uint256 _amount) external payable{
        require(_amount > 0, "Contribution amount must be greater than 0");
        uint256 oldContribution = daiContribution[msg.sender];
        uint256 balanceDAIOld = IERC20(dai).balanceOf(address(this));
        
        IERC20 token = IERC20(_token);
        uint256 balanceTokenOld = token.balanceOf(address(this));
        token.transferFrom(msg.sender,address(this),_amount);
        uint256 balanceTokenNew = token.balanceOf(address(this));
        uint256 tokenAmt = balanceTokenNew.sub(balanceTokenOld);
        if(_token != address(WETH)){
            address[] memory path1 = new address[](3);
            path1[0] = address(_token);
            path1[1] = address(WETH);
            path1[2] = address(dai);
            token.approve(address(uniswapV2Router), _amount); //router
            
            uniswapV2Router.swapExactTokensForTokens(tokenAmt, 0, path1, address(this), 2e9);
        } else {    //token is WETH
            address[] memory path2 = new address[](2);
            path2[0] = address(_token);
            path2[1] = address(dai);
            token.approve(address(uniswapV2Router), _amount); //router
            
            uniswapV2Router.swapExactTokensForTokens(tokenAmt, 0, path2, address(this), 2e9);
        }

        // uint256 amountOut = sellTokenForDAI(_token, _amount);
        uint256 balanceDAINew = IERC20(dai).balanceOf(address(this));
        uint256 gain = balanceDAINew.sub(balanceDAIOld);   
        
        require(balanceDAIOld < balanceDAINew, "DAI Received From Sale Insufficient");
        totalDAIContribution = totalDAIContribution.add(gain);
        daiContribution[msg.sender] = daiContribution[msg.sender].add(gain);
        require(daiContribution[msg.sender] > oldContribution, "No new contribution added.");
        if (oldContribution == 0 ) {
            contributors.push(msg.sender);
            emit NewContribution(_amount, msg.sender);
        } else{
            emit Contribution(gain, msg.sender);
        } 
    }

    //ETH contribution
    receive() external payable active(){
        require(msg.value > 0, 'Value must be greater than 0');
        uint256 oldContribution = daiContribution[msg.sender];

        uint256 oldBalance = WETH.balanceOf(address(this));
        WETH.deposit{value : msg.value}();
        uint256 newBalance = WETH.balanceOf(address(this));
        require(newBalance > oldBalance, 'No wETH received from wrap');

        uint256 wETHamt = newBalance.sub(oldBalance);

        uint256 preDAIBalance = dai.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(dai);
        uniswapV2Router.swapExactTokensForTokens(wETHamt, 0, path, address(this), 2e9);
        uint256 postDAIBalance = dai.balanceOf(address(this));
        require(postDAIBalance > preDAIBalance, "Error: Swap");
        uint256 amountOut = postDAIBalance.sub(preDAIBalance);

        require(amountOut > 0, 'No DAI received from sale');
        totalDAIContribution = totalDAIContribution.add(amountOut);
        daiContribution[msg.sender] = daiContribution[msg.sender].add(amountOut);
        require(daiContribution[msg.sender] > oldContribution, "No new contribution added.");
        if ( oldContribution == 0 ) {
            contributors.push(msg.sender);
            emit NewContribution(amountOut, msg.sender);
        }else{
            emit Contribution(amountOut, msg.sender);
        }
    }

    function setupJCEwdai() external isMesaj() {
        JCEwdai = IUniswapV2Pair(uniswapV2Factory.getPair(address(JCE), address(wdai)));
        if (address(JCEwdai) == address(0)) {
            JCEwdai = IUniswapV2Pair(uniswapV2Factory.createPair(address(JCE), address(wdai)));
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
        uint256[] memory amountsJCE = uniswapV2Router.swapExactTokensForTokens(buyAmount, 0, path, address(this), 2e9);
        totalJCEBought = JCE.balanceOf(address(this));
    }

    function distribute() internal {
        require (!distributionComplete, "Distribution complete");
        uint256 totalDAI = totalDAIContribution;
        
        require (totalDAI > 0, "No Liquidity Generated");
        distributionComplete = true;
        totalDAICollected = totalDAI;

        TransferPortal portal = TransferPortal(address(JCE.transferPortal()));
        portal.setFreeTransfers(true);

        createJCEwdaiLiquidity(totalDAICollected);
        createDAILiquidity(totalDAICollected);
        preBuyForGroup(totalDAICollected);

        dai.transfer(mesaj, dai.balanceOf(address(this))); //Leftover DAI is Dev fund/payment
  
        portal.setFreeTransfers(false);
    }

    function createDAILiquidity(uint256 totalDAI) internal {
        //Wrap half allocated DAI liquidity into wDAI
        wdai.deposit(totalDAI.mul(daiPoolPercent).div(20000));
        
        //Deposit DAI/wDAI at 1:1 ratio - use same wDAI balance as parameter to ensure 1:1 (not a mistake)
        (,,totalDAIwdai) = uniswapV2Router.addLiquidity(address(dai), address(wdai), wdai.balanceOf(address(this)), wdai.balanceOf(address(this)), 0, 0, address(this), block.timestamp);

        //Transfer DAI-wDAI LP Tokens to Juice Treasury
        IERC20(uniswapV2Factory.getPair(address(dai), address(wdai))).transfer(treasury,totalDAIwdai);
    }

    function createJCEwdaiLiquidity(uint256 totalDAI) internal {
        // Create WDAI/JCE Liquidity Pool
        wdai.deposit(totalDAI.mul(poolPercent).div(10000));

        (,,totalJCEwdai) = uniswapV2Router.addLiquidity(address(JCE),address(wdai), JCE.totalSupply(), wdai.balanceOf(address(this)), 0, 0, address(this), block.timestamp);
        lpToken = IERC20(uniswapV2Factory.getPair(address(JCE),address(wdai)));
    }

    function claim() public {
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

    function _claim(address _to, uint256 _contribution) internal {
        uint256 totalDAI = totalDAICollected;

        // Send JCE/wDAI LP tokens
        uint256 share = _contribution.mul(totalJCEwdai) / totalDAI;
        if (share > lpToken.balanceOf(address(this))) {
            share = lpToken.balanceOf(address(this));
        }
        lpToken.transfer(_to, share);  

        // Send JCE Token
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