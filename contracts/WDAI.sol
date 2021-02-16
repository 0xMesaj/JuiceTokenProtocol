// Wrapped DAI - wDAI
// wDAI and DAI always exchange 1:1

pragma solidity ^0.7.0;

import 'hardhat/console.sol';

import "./ERC20.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./SafeMath.sol";

contract WDAI is ERC20{
    using SafeMath for uint256;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    IERC20 public immutable wrappedToken;
    ILockedLiqCalculator public lockedLiqCalculator;

    mapping (address => bool) public quaestor;
    mapping (address => bool) public treasury;

    address owner;

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }

    constructor (IERC20 _wrappedToken, address _treasury, string memory _name, string memory _symbol) ERC20 (_name, _symbol) {
        wrappedToken = _wrappedToken;
        treasury[_treasury] = true;
        quaestor[msg.sender] = true;
        owner = msg.sender;
    }

    function setLiquidityCalculator(ILockedLiqCalculator _lockedLiqCalculator) external ownerOnly(){
        lockedLiqCalculator = _lockedLiqCalculator;
    }

    function promoteQuaestor(address sweeper, bool _isApproved) external ownerOnly(){
        quaestor[sweeper] = _isApproved;
    }

    function designateTreasury(address _treasury, bool _isApproved) external ownerOnly(){
        treasury[_treasury] = _isApproved;
    }

    function fund(address to) public returns (uint256 amountSwept){
        require (treasury[to], "Error: Destination Address Not Approved Treasury");
        require (quaestor[msg.sender], "Error: Quaestors only");
        amountSwept = lockedLiqCalculator.calculateSubFloor(wrappedToken, address(this));
        console.log("Amount Swept = %s",amountSwept);
        if (amountSwept > 0) {
            wrappedToken.transferFrom(address(this),to, amountSwept);
        }
    }

    function fundAmt(address to, uint256 amt) public {
        require (treasury[to], "Error: Destination Address Not Approved Treasury");
        require (quaestor[msg.sender], "Error: Quaestors only");
        uint256 freeableDAI = lockedLiqCalculator.calculateSubFloor(wrappedToken, address(this));
        require(freeableDAI > amt, "Error: Funding amount greater than freeable DAI");
        console.log("Amount Swept = %s",amt);
        if (amt > 0) {
            wrappedToken.transferFrom(address(this), to, amt);
        }
    }

    //deposit DAI, withdraw wDAI
    function deposit(uint256 _amount) public{
        // console.log('%s is Depositing %s', msg.sender, _amount);
        wrappedToken.transferFrom(msg.sender,address(this), _amount);
        _mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount); 
    }

    //withdraw DAI, deposit wDAI
    function withdraw(uint256 _amount) public{
        _burn(msg.sender, _amount);
        wrappedToken.transferFrom(address(this),msg.sender, _amount);
        emit Withdrawal(msg.sender, _amount);

    }  


}