// Wrapped DAI - wDAI
// wDAI and DAI always exchange 1:1

pragma solidity ^0.7.0;

import "./SafeERC20.sol";
import "./ERC20.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IBookVault.sol";
import "./uniswap/IUniswapV2Factory.sol";
import "./SafeMath.sol";

contract WDAI is ERC20{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;


    string public constant contract_name = "Book Treasury";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event ProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event VoteCast(address voter, uint proposalId, bool support, uint votes);

    mapping (address => bool) public quaestor;
    mapping (address => bool) public treasury;

    uint public proposalCount;
    IERC20 public immutable wrappedToken;
    IUniswapV2Factory factory;
    ILockedLiqCalculator public lockedLiqCalculator;
    address mesaj;
    IERC20 BOOK;
    IBookVault vault;

    struct Proposal {
        uint id;
        address upgrade;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        uint minVotes;
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


    modifier mesajOnly(){
        require (msg.sender == mesaj, "Mesaj only");
        _;
    }

    constructor ( IBookVault _vault,IERC20 _BOOK, IERC20 _wrappedToken, address _treasury, IUniswapV2Factory _factory, string memory _name, string memory _symbol) ERC20 (_name, _symbol) {
        wrappedToken = _wrappedToken;
        treasury[_treasury] = true;
        quaestor[_treasury] = true;
        quaestor[msg.sender] = true;

        vault = _vault;
        BOOK = _BOOK;
        mesaj = msg.sender;
    }

    /* Set the address for initial lockedLiqCalculator, cannot be recalled after first execution -
       Only way to change lockedLiqCalculator is through governance proposals */
    function setLiquidityCalculator(ILockedLiqCalculator _lockedLiqCalculator) external mesajOnly(){
        require(lockedLiqCalculator == 0x0, "Function no longer callable after first execution");
        lockedLiqCalculator = _lockedLiqCalculator;
    }

    function promoteQuaestor(address sweeper, bool _isApproved) external mesajOnly(){
        quaestor[sweeper] = _isApproved;
    }

    function abdicate(address shame) public{
        require(mesaj != shame, "Et tu, Brute?");
        require (quaestor[msg.sender], "Error: Quaestors only");
        treasurers[shame] = false;
    }

    function designateTreasury(address _treasury, bool _isApproved) external mesajOnly(){
        require (quaestor[msg.sender], "Error: Quaestors only");
        treasury[_treasury] = _isApproved;
    }

    function initializeTreasuryBalance(address to) public{
        require (treasury[to], "Error: Destination Address Not Approved Treasury");
        require (quaestor[msg.sender], "Error: Quaestors only");
        
        uint256 fundAmount = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));
        IBookVault(to).initializeTreasury(fundAmount);
        if (fundAmount > 0) {
            wrappedToken.transferFrom(address(this),to, fundAmount);
        }
    }

    function fund(address to) public returns (uint256 fundAmount){
        require (treasury[to], "Error: Destination Address Not Approved Treasury");
        require (quaestor[msg.sender], "Error: Quaestors only");
        fundAmount = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));

        if (fundAmount > 0) {
            wrappedToken.transferFrom(address(this),to, fundAmount);
        }
    }

    function fundAmt(address to, uint256 amt) public {
        require (treasury[to], "Error: Destination Address Not Approved Treasury");
        require (quaestor[msg.sender], "Error: Quaestors only");
        uint256 freeableDAI = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));
        require(freeableDAI > amt, "Error: Requested Funding Amount Greater Than Freeable DAI");

        if (amt > 0) {
            wrappedToken.transferFrom(address(this), to, amt);
        }
    }

    // Wrap: DAI -> wDAI
    function deposit(uint256 _amount) public{
        wrappedToken.transferFrom(msg.sender,address(this), _amount);
        _mint(msg.sender, _amount);
        emit Deposit(msg.sender, _amount); 
    }

    // Unwrap: wDAI -> DAI
    function withdraw(uint256 _amount) public{
        _burn(msg.sender, _amount);
        wrappedToken.transferFrom(address(this),msg.sender, _amount);
        emit Withdrawal(msg.sender, _amount);
    }  

    function proposeStrategy(address _strategy) public {
        require (quaestor[msg.sender], "Error: Quaestors only");
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760);

        proposalCount++;

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.upgrade = _strategy;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.minVotes = getMinRequiredVotes();
        p.canceled = false;
        p.executed = false;
        emit ProposalCreated(p.id, _startBlock, _endBlock, _strategy);
    }

    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
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
        uint256 votes = BOOK.balanceOf(voter);

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

    // Min Required Votes to Reject is 51% of the Circulating Book Token
    // Subtract the BOOK within the LPs
    function getMinRequiredVotes() internal view returns(uint256 amt){
        uint256 poolNum = vault.poolInfoCount();
        uint256 pooledBookCount = 0;
        for(uint i=0;i<poolNum;i++){
            pooledBookCount = pooledBookCount.add(vault.getPooledBook(i));
        }
        uint bookSupply = BOOK.totalSupply();
        amt = bookSupply.sub(pooledBookCount).mul(51).div(100);
    }

    function judgeProposal(uint proposalID) public {
        Proposal storage p = proposals[proposalID];
        require(block.timestamp > p.endBlock, 'Proposal Ongoing');
        if((p.forVotes > p.againstVotes) || (p.againstVotes < p.minVotes)){
            lockedLiqCalculator = ILockedLiqCalculator(p.upgrade);
            p.executed = true;
        }else{
            p.canceled = true;
        }
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

    receive() external payable { }



}