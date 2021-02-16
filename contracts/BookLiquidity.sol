pragma solidity ^0.7.0;

/* ROOTKIT:
A wrapper for liquidity tokens so they can be distributed
but not allowing for removal of liquidity
*/


import "./uniswap/IUniswapV2Pair.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

contract BookLiquidity is ERC20{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    IERC20 public immutable wrappedToken;

    ILockedLiqCalculator public lockedLiqCalculator;
    address owner;
    mapping (address => bool) public sweepers;

    constructor (IERC20 _wrappedToken, string memory _name, string memory _symbol) ERC20(_name, _symbol){        
        if (_wrappedToken.decimals() != 18) {
            _setupDecimals(_wrappedToken.decimals());
        }
        wrappedToken = _wrappedToken;
        owner = msg.sender;
    }

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }

    function _beforeWithdrawTokens(uint256) internal pure{ 
        revert("RootKit liquidity is locked");
    }

    function setFloorCalculator(ILockedLiqCalculator _lockedLiqCalculator) public ownerOnly(){
        lockedLiqCalculator = _lockedLiqCalculator;
    }

    function setSweeper(address sweeper, bool allow) public ownerOnly(){
        sweepers[sweeper] = allow;
    }

    function sweepFloor(address to) public returns (uint256 amountSwept){
        require (to != address(0));
        require (sweepers[msg.sender], "Sweepers only");
        amountSwept = lockedLiqCalculator.calculateSubFloor(wrappedToken, address(this));
        if (amountSwept > 0) {
            wrappedToken.safeTransfer(to, amountSwept);
        }
    }

    function depositTokens(uint256 _amount) public{
        uint256 myBalance = wrappedToken.balanceOf(address(this));
        wrappedToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 received = wrappedToken.balanceOf(address(this)).sub(myBalance);
        _mint(msg.sender, received);
        emit Deposit(msg.sender, _amount);
    }

    function withdrawTokens(uint256 _amount) public{
        _beforeWithdrawTokens(_amount);
        _burn(msg.sender, _amount);
        uint256 myBalance = wrappedToken.balanceOf(address(this));
        wrappedToken.safeTransfer(msg.sender, _amount);
        require (wrappedToken.balanceOf(address(this)) == myBalance.sub(_amount), "Transfer not exact");
        emit Withdrawal(msg.sender, _amount);
    }


}