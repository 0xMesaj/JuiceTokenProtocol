pragma solidity ^0.7.0;
import "./IERC20.sol";

interface IWDAI {
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    function wrappedToken() external view returns (IERC20);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function allowance(address _owner, address _spender) external view returns (uint256);
    function approve(address _spender, uint256 _amount) external returns (bool);
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
    function burn(uint256 _value) external returns (bool);

    function fund(address to) external returns (uint256);
    function fundAmt(address to, uint256 amt) external returns (uint256);

    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}