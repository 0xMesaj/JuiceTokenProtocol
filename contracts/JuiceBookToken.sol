pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./interfaces/ITransferPortal.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IJuiceBookVault.sol";
import "./uniswap/IUniswapV2Factory.sol";

/*
    BOOK Token has a transfer portal that is changeable through on-chain governance
    Total Initial Supply: 28 Million
*/

contract JuiceBookToken is ERC20{
    using SafeMath for uint256;

    string public constant contract_name = "JuiceBook";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    address public mesaj;

    ITransferPortal public transferPortal;
    IJuiceBookVault vault;
    uint public proposalCount;

    modifier mesajOnly(){
        require (msg.sender == mesaj, "Mesaj only");
        _;
    }

    struct Proposal {
        uint id;
        address upgrade;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
        mapping (address => Receipt) receipts;
    }

    struct Receipt {
        bool hasVoted;
        bool support;
        uint256 votes;
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Executed
    }

    mapping(address => bool) public treasurers;
    mapping (uint => Proposal) public proposals;

    event ProposalCreated(uint id, uint startBlock, uint endBlock, address strategy);
    event VoteCast(address voter, uint proposalId, bool support, uint votes);

    modifier isTreasurer(){
        require (treasurers[msg.sender], "Treasurers only");
        _;
    }

    constructor( string memory _name, string memory _symbol ) ERC20(_name,_symbol) {
        mesaj = msg.sender;
        treasurers[mesaj] = true;

        _mint(mesaj, 28000000000000000000000000); // 28 Milli
    }

    function setTreasurer(address appointee) public isTreasurer(){
        require(!treasurers[appointee], "Appointee is already treasurer");
        treasurers[appointee] = true;
    }

    function abdicate(address shame) public isTreasurer(){
        require(mesaj != shame, "Et tu, Brute?");
        treasurers[shame] = false;
    }

    function proposeUpgrade(address _upgrade) public isTreasurer(){
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760);

        proposalCount++;

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.upgrade = _upgrade;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.canceled = false;
        p.executed = false;
        emit ProposalCreated(p.id, _startBlock, _endBlock, _upgrade);
    }

    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(contract_name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "castVoteBySig: invalid signature");
        return _castVote(signatory, proposalId, support);
    }

    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "_castVote: voter already voted");
        uint256 votes = balanceOf(voter);

        if (support) {
            proposal.forVotes = votes.add(proposal.forVotes);
        } else {
            proposal.againstVotes = votes.add(proposal.againstVotes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    // Min Required Votes to Reject is 51% of the Circulating JBT
    // Subtract the JBT within the LPs
    function getMinRequiredVotes() internal view returns(uint256 amt){
        uint256 poolNum = vault.poolInfoCount();
        uint256 pooledJBTCount = 0;
        for(uint i=0;i<poolNum;i++){
            pooledJBTCount = pooledJBTCount.add(vault.getPooledJBT(i));
        }
        uint JBTSupply = totalSupply;
        amt = JBTSupply.sub(pooledJBTCount).mul(51).div(100);
    }

    function judgeProposal(uint proposalID) public {
        Proposal storage p = proposals[proposalID];
        uint MIN_VOTES = getMinRequiredVotes();
        require(block.timestamp > p.endBlock, 'Proposal Ongoing');
        if((p.forVotes > p.againstVotes) || p.againstVotes < MIN_VOTES){
            transferPortal = ITransferPortal(p.upgrade);
            p.executed = true;
        }else{
            p.canceled = true;
        }
    }

    function setTransferPortal(ITransferPortal _transferPortal) external mesajOnly(){
        transferPortal = _transferPortal;
    }

    
    function burn(uint256 amount) public virtual returns(bool) {
        _burn(msg.sender, amount);
        return true;
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

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Succeeded;
        } 
    }

    function getChainId() internal pure returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function setJBTVault( IJuiceBookVault _vault ) external isTreasurer(){
        require( address(vault) == address(0x0), "Vault already set");
        vault = _vault;
    }

    receive() external payable { }

}