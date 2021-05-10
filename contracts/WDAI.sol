// Wrapped DAI - wDAI
// wDAI and DAI always exchange 1:1 through deposit/withdraw functions
// Proposal Type for Governance:
// TRUE for Locked Liquidity Calc Proposal, FALSE for Treasury Proposal

pragma solidity ^0.7.0;

import "./SafeERC20.sol";
import "./ERC20.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IJuiceVault.sol";
import "./uniswap/IUniswapV2Factory.sol";
import "./SafeMath.sol";

contract WDAI is ERC20{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    string public constant contract_name = "WDAI";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    event LiquidityProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event LiquidityVoteCast(address voter, uint proposalId, bool support, uint votes);
    event TreasuryProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event TreasuryVoteCast(address voter, uint proposalId, bool support, uint votes);

    mapping (address => bool) public quaestor;
    mapping (address => bool) public treasury;

    uint public liquidityProposalCount;
    uint public treasuryProposalCount;
    IERC20 public immutable wrappedToken;
    IUniswapV2Factory factory;
    ILockedLiqCalculator public lockedLiqCalculator;
    address mesaj;
    IERC20 JCE;
    IJuiceVault vault;
    bool initialized = false;

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

    mapping (address => bool) public treasurers;
    mapping (uint => Proposal) public liquidityProposals;
    mapping (uint => Proposal) public treasuryProposals;


    modifier quaestorOnly(){
        require (quaestor[msg.sender], "Error: Quaestors only");
        _;
    }

    constructor ( IJuiceVault _vault,IERC20 _JCE, IERC20 _wrappedToken, address _treasury, IUniswapV2Factory _factory, string memory _name, string memory _symbol ) ERC20 (_name, _symbol) {
        wrappedToken = _wrappedToken;
        treasury[_treasury] = true;
        quaestor[_treasury] = true;
        quaestor[msg.sender] = true;

        vault = _vault;
        JCE = _JCE;
        mesaj = msg.sender;
    }

    /* Set the address for initial lockedLiqCalculator, cannot be recalled after first execution -
       Only way to change lockedLiqCalculator is through on-chain governance proposals */
    function setLiquidityCalculator(ILockedLiqCalculator _lockedLiqCalculator) external quaestorOnly(){
        require(address(lockedLiqCalculator) == address(0x0), "Function no longer callable after first execution");
        lockedLiqCalculator = _lockedLiqCalculator;
    }

    function promoteQuaestor(address _approvee, bool _isApproved) external quaestorOnly(){
        quaestor[_approvee] = _isApproved;
    }

    function abdicate(address _shame) public quaestorOnly(){
        require(mesaj != _shame, "Et tu, Brute?");
        treasurers[_shame] = false;
    }

    function designateTreasury(address _treasury, bool _isApproved) external quaestorOnly(){
        require(!initialized, "Function no longer callable after first execution");
        treasury[_treasury] = _isApproved;
        initialized = true;
    }

    function initializeTreasuryBalance(address _to) public quaestorOnly(){
        require (treasury[_to], "Error: Destination Address Not Approved Treasury");
        
        uint256 fundAmount = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));
        IJuiceVault(_to).initializeTreasury(fundAmount);
        if (fundAmount > 0) {
            wrappedToken.transferFrom(address(this), _to, fundAmount);
        }
    }

    function fund(address _to) public quaestorOnly() returns (uint256 fundAmount){
        require (treasury[_to], "Error: Destination Address Not Approved Treasury");
        fundAmount = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));

        if (fundAmount > 0) {
            wrappedToken.transferFrom(address(this), _to, fundAmount);
        }
    }

    function fundAmt(address _to, uint256 _amt) public quaestorOnly(){
        require (treasury[_to], "Error: Destination Address Not Approved Treasury");
        uint256 freeableDAI = lockedLiqCalculator.calculateLockedwDAI(wrappedToken, address(this));
        require(freeableDAI > _amt, "Error: Requested Funding Amount Greater Than Freeable DAI");

        if (_amt > 0) {
            wrappedToken.transferFrom(address(this), _to, _amt);
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

    function proposeLiquidityStrategy(address _strategy) public quaestorOnly(){
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760);

        liquidityProposalCount++;

        Proposal storage p = liquidityProposals[liquidityProposalCount];
        p.id = liquidityProposalCount;
        p.upgrade = _strategy;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.minVotes = getMinRequiredVotes();
        p.canceled = false;
        p.executed = false;
        emit LiquidityProposalCreated(p.id, _startBlock, _endBlock, _strategy);
    }

    function proposeTreasuryStrategy(address _strategy) public quaestorOnly(){
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760);

        treasuryProposalCount++;

        Proposal storage p = treasuryProposals[liquidityProposalCount];
        p.id = treasuryProposalCount;
        p.upgrade = _strategy;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.minVotes = getMinRequiredVotes();
        p.canceled = false;
        p.executed = false;
        emit TreasuryProposalCreated(p.id, _startBlock, _endBlock, _strategy);
    }

    function castVote(uint proposalId, bool proposalType, bool support) public {
        return _castVote(msg.sender, proposalId, proposalType, support);
    }

    function castVoteBySig(uint proposalId, bool proposalType, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "castVoteBySig: invalid signature");
        return _castVote(signatory, proposalId, proposalType, support);
    }

    function _castVote(address voter, uint proposalId, bool proposalType, bool support) internal {
        require(state(proposalId,proposalType) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        Proposal storage proposal = (proposalType ? liquidityProposals[proposalId]: treasuryProposals[proposalId]);
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "_castVote: voter already voted");
        uint256 votes = JCE.balanceOf(voter);

        if (support) {
            proposal.forVotes = votes.add(proposal.forVotes);
        } else {
            proposal.againstVotes = votes.add(proposal.againstVotes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;
        if(proposalType){
            emit LiquidityVoteCast(voter, proposalId, support, votes);
        } else {
            emit TreasuryVoteCast(voter, proposalId, support, votes);
        }
        
    }

    // Min Required Votes to Reject is 51% of the Circulating JCE Token
    // Subtract the JCE within the LPs
    function getMinRequiredVotes() internal view returns(uint256 amt){
        uint256 poolNum = vault.poolInfoCount();
        uint256 pooledJCECount = 0;
        for(uint i=0;i<poolNum;i++){
            pooledJCECount = pooledJCECount.add(vault.getPooledJCE(i));
        }
        uint JCESupply = JCE.totalSupply();
        amt = JCESupply.sub(pooledJCECount).mul(51).div(100);
    }

    function judgeProposal(uint proposalId, bool proposalType) public {
        Proposal storage p = (proposalType ? liquidityProposals[proposalId]: treasuryProposals[proposalId]);
        require(block.timestamp > p.endBlock, 'Proposal Ongoing');
        if((p.forVotes > p.againstVotes) || (p.minVotes > p.againstVotes)){
            if(proposalType){
                treasury[p.upgrade] = true;
                p.executed = true;
            }else{
                lockedLiqCalculator = ILockedLiqCalculator(p.upgrade);
                p.executed = true;
            }

        }else{
            p.canceled = true;
        }
    }

    function state(uint proposalId, bool proposalType) public view returns (ProposalState) {
        if(proposalType){
            require(liquidityProposalCount >= proposalId && proposalId > 0, "state: invalid liquidity proposal id");
        } else {
            require(treasuryProposalCount >= proposalId && proposalId > 0, "state: invalid treasury proposal id");
        }
        
        Proposal storage proposal = (proposalType ? liquidityProposals[proposalId]: treasuryProposals[proposalId]);
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        } else if (proposal.forVotes >= proposal.againstVotes || proposal.forVotes < proposal.minVotes) {
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