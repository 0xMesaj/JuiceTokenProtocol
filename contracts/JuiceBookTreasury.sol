pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWDAI.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./interfaces/IJuiceBookToken.sol";
import "./interfaces/IJuiceBookVault.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";


/*
    JuiceBook Treasury holds DAI liquidity for the BOOK token protocol - to be utilized in approved
    strategies to generate profit. These strategies are approved through on-chain voting
    with the BOOK token
*/

contract JuiceBookTreasury {
    using SafeERC20 for IERC20;
    using SafeMath for uint;


    string public constant name = "JuiceBook Treasury";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    uint public proposalCount;
    uint256 MIN_REQUIREMENT = uint(-1);
    address mesaj;
    IJuiceBookToken JBT;
    IERC20 DAI;
    IWDAI WDAI;
    IUniswapV2Factory factory;
    IUniswapV2Router02 router;
    ILockedLiqCalculator BookLiqCalculator;
    IJuiceBookVault vault;
    
    struct Proposal {
        uint id;
        address strategy;
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

    mapping(address => bool) public strategies;
    mapping(address => bool) public treasurers;
    mapping (uint => Proposal) public proposals;

    event ProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event VoteCast(address voter, uint proposalId, bool support, uint votes);
    
    modifier isTreasurer(){
        require (treasurers[msg.sender], "Treasurers only");
        _;
    }

    function setTreasurer(address appointee) public isTreasurer(){
        require(!treasurers[appointee], "Appointee is already treasurer.");
        treasurers[appointee] = true;
    }

    function abdicate(address shame) public isTreasurer(){
        require(mesaj != shame, "Et tu, Brute?");
        treasurers[shame] = false;
    }
    
    constructor( IJuiceBookVault _vault, address _sportsBook, IERC20 _DAI,  IJuiceBookToken _JBT, ILockedLiqCalculator _BookLiqCalculator, IUniswapV2Factory _factory, IUniswapV2Router02 _router ) {
        factory = _factory;
        router = _router;
        BookLiqCalculator = _BookLiqCalculator;
        JBT = _JBT;
        DAI = _DAI;

        vault = _vault;
        mesaj = msg.sender;
        strategies[_sportsBook] = true;
        DAI.approve(_sportsBook,uint(-1));
        treasurers[mesaj] = true;
    }

    function setWDAI( IWDAI _wdai ) external isTreasurer(){
        require( address(WDAI) == address(0x0), "Wrapped DAI already set");
        WDAI = _wdai;
        WDAI.approve(address(router),uint(-1));
    }

    function initializeTreasury( uint256 _amount ) public{
        require(msg.sender == address(WDAI), "Invalid Access");
        //Must maintain 100% reserve of initial DAI funded
        MIN_REQUIREMENT = _amount;    
    }

    //Set allowance for strategy to new _amount
    function setAllowance( uint256 _amount, address _strategy) external isTreasurer(){
        require(strategies[_strategy], "Requested address not valid strategy");
        uint DAIreserve = DAI.balanceOf(address(this));
        require(_amount < DAIreserve);
        DAI.approve(_strategy,_amount);
    }

    function numberGoUp( uint _amt ) external isTreasurer(){
        uint256 check = DAI.balanceOf(address(this)).sub(_amt);
        require(check > MIN_REQUIREMENT, "Treasury below buying threshold");
        
        DAI.approve(address(WDAI),_amt);
        WDAI.deposit(_amt);

        address[] memory path = new address[](2);
        path[0] = address(WDAI);
        path[1] = address(JBT);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(WDAI.balanceOf(address(this)), 0, path, address(this), 2e9);
        
        JBT.burn(JBT.balanceOf(address(this)));
        uint256 wDAIamt = BookLiqCalculator.simulateSell(DAI, address(WDAI));
        WDAI.fund(address(this));
        uint256 DAIbacking = DAI.balanceOf(address(WDAI));
        require(DAIbacking > wDAIamt, "Number cannot go that high...yet");
    }

    function proposeStrategy(address _strategy) public isTreasurer(){
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760);

        proposalCount++;

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.strategy = _strategy;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
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
        uint256 votes = JBT.balanceOf(voter);

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

    // Min Required Votes to Reject is 51% of the Circulating JBT Token
    // Subtract the JBT within the LPs
    function getMinRequiredVotes() internal view returns(uint256 amt){
        uint256 poolNum = vault.poolInfoCount();
        uint256 pooledJBTCount = 0;
        for(uint i=0;i<poolNum;i++){
            pooledJBTCount = pooledJBTCount.add(vault.getPooledJBT(i));
        }
        uint JBTSupply = JBT.totalSupply();
        amt = JBTSupply.sub(pooledJBTCount).mul(51).div(100);
    }

    function judgeProposal(uint proposalID) public {
        Proposal storage p = proposals[proposalID];
        uint MIN_VOTES = getMinRequiredVotes();
        require(block.timestamp > p.endBlock, 'Proposal Ongoing');
        if((p.forVotes > p.againstVotes) || p.againstVotes < MIN_VOTES){
            strategies[p.strategy] = true;
            DAI.approve(p.strategy,uint(-1));
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