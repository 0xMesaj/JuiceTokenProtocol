pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./interfaces/ITransferPortal.sol";
import "./ERC20.sol";
import 'hardhat/console.sol';

contract BookToken is ERC20{
    using SafeMath for uint256;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    address public owner;
    ITransferPortal public transferPortal;

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC20(_name,_symbol) {
        owner = msg.sender;
        _mint(owner, 28000000000000000000000000); //28 Milli
    }

    function setTransferPortal(ITransferPortal _transferPortal) external ownerOnly(){
        transferPortal = _transferPortal;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        ITransferPortal _transferPortal = transferPortal;
        uint256 remaining = amount;
        if (address(_transferPortal) != address(0)) {
            TransferPortalTarget[] memory targets = _transferPortal.handleTransfer(msg.sender, sender, recipient, amount);            
            for (uint256 x = 0; x < targets.length; ++x) {
                (address dest, uint256 amt) = (targets[x].destination, targets[x].amount);
                remaining = remaining.sub(amt, "Transfer too much");
                _balanceOf[dest] = _balanceOf[dest].add(amt);
            }
        }
        _balanceOf[sender] = _balanceOf[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balanceOf[recipient] = _balanceOf[recipient].add(remaining);
        emit Transfer(sender, recipient, amount);
    }

    function burn(uint256 _value) public returns (bool) {
        console.log("in burn supply=%s",totalSupply);
        // Requires that the message sender has enough tokens to burn
        require(_value <= _balanceOf[msg.sender]);

        // Subtracts _value from callers balance and total supply
        _balanceOf[msg.sender] = _balanceOf[msg.sender].sub(_value);
        totalSupply = totalSupply.sub(_value);
        console.log("in post burn supply=%s",totalSupply);
        // Since you cant actually burn tokens on the blockchain, sending to address 0, which none has the private keys to, removes them from the circulating supply
        return true;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override virtual { }
}