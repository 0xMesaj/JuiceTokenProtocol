// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWDAI.sol";
import "./interfaces/ILockedLiqCalculator.sol";
import "./interfaces/IJuiceToken.sol";
import "./interfaces/IJuiceVault.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";

/*
    Juice Treasury holds DAI liquidity for the Juice token protocol - to be utilized in approved
    strategies to generate profit. These strategies are approved through on-chain voting
    with JCE
*/

contract JuiceTreasury {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    string public constant name = "Juice Treasury";
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    uint public proposalCount;
    uint public handlerProposalCount;
    uint256 MIN_REQUIREMENT = uint(-1);
    address mesaj;

    IJuiceToken JCE;
    IERC20 DAI;
    IWDAI WDAI;
    IUniswapV2Factory factory;
    IUniswapV2Router02 router;
    ILockedLiqCalculator liqCalculator;
    IJuiceVault vault;
    
    struct Proposal {
        uint id;
        address strategy;
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

    mapping(address => bool) public strategies;
    mapping(address => bool) public treasurers;
    mapping(uint => Proposal) public proposals;
    mapping(uint => Proposal) public handlerProposals;

    event ProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event VoteCast(address voter, uint proposalId, bool support, uint votes);
    event HandlerProposalCreated(uint id, uint startBlock, uint endBlock, address upgrade);
    event HandlerVoteCast(address voter, uint proposalId, bool support, uint votes);
    
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
    
    constructor( IJuiceVault _vault, address _sportsBook, address _xdaiBridge, IERC20 _DAI,  IJuiceToken _JCE, ILockedLiqCalculator _liqCalculator) {
        factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        liqCalculator = _liqCalculator;
        JCE = _JCE;
        DAI = _DAI;

        vault = _vault;
        mesaj = msg.sender;

        strategies[_sportsBook] = true; // Approve mainnet sports book
        DAI.approve(_sportsBook,uint(-1));

        strategies[_xdaiBridge] = true; // Approve xDAI bridge/SportsBook
        DAI.approve(_xdaiBridge,uint(-1));

        DAI.approve(address(WDAI),uint(-1)); // For wrapping DAI in market buy
        treasurers[mesaj] = true;
    }

    function setWDAI( IWDAI _wdai ) external isTreasurer() {
        require( address(WDAI) == address(0x0), "Wrapped DAI already set");
        WDAI = _wdai;
        WDAI.approve(address(router),uint(-1));
    }

    function initializeTreasury( uint256 _amount ) public {
        require(msg.sender == address(WDAI), "Invalid Access");
        uint256 split = _amount.div(2);  //Half goes to xDAI network
        //Must maintain reserve of initial funding
        MIN_REQUIREMENT = split;
    }

    // Set allowance for strategy to new _amount
    function setAllowance( uint256 _amount, address _strategy) external isTreasurer() {
        require(strategies[_strategy], "Requested address not valid strategy");
        DAI.approve(_strategy,_amount);
        if(_amount == 0){
            strategies[_strategy] = false;  //Remove Strategy if new allowance is 0
        }
    }

    /* 
        Spend profits generated from strategies to use
        _amt DAI and market buy JCE with it
    */
    function numberGoUp( uint _amt ) external isTreasurer(){
        uint256 check = DAI.balanceOf(address(this)).sub(_amt);
        require(check > MIN_REQUIREMENT, "Treasury below buying threshold");
        
        WDAI.deposit(_amt); // DAI -> wDAI (wrap)

        // Purchase JCE with wDAI
        address[] memory path = new address[](2);
        path[0] = address(WDAI);
        path[1] = address(JCE);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(WDAI.balanceOf(address(this)), 0, path, address(this), 2e9);
        
        // Burn purchased JCE then retrieve DAI back through fund()
        JCE.burn(JCE.balanceOf(address(this)));
        WDAI.fund(address(this));

        // Simulate selling all circulating JCE and ensure wDAI-DAI peg is backed
        uint256 wDAIamt = liqCalculator.simulateSell(address(WDAI));
        uint256 DAIbacking = DAI.balanceOf(address(WDAI));
        require(DAIbacking > wDAIamt, "Number cannot go that high...yet");
    }

    // Treasury is given all DAI-wDAI LP tokens and through 
    // on-chain governance, the LP tokens can be sent elsewhere
    function proposeHandlerStrategy(address _handler) public isTreasurer(){
        uint _startBlock = block.number;
        uint _endBlock = _startBlock.add(5760); //1 Day assuming ~15 second blocks

        handlerProposalCount++;

        Proposal storage p = proposals[handlerProposalCount];
        p.id = handlerProposalCount;
        p.strategy = _handler;
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.forVotes = 0;
        p.againstVotes = 0;
        p.minVotes = getMinRequiredVotes();
        p.canceled = false;
        p.executed = false;
        emit HandlerProposalCreated(p.id, _startBlock, _endBlock, _handler);
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
        p.minVotes = getMinRequiredVotes();
        p.canceled = false;
        p.executed = false;
        emit ProposalCreated(p.id, _startBlock, _endBlock, _strategy);
    }

     function castVote(uint _proposalId, bool _proposalType, bool _support) public {
        return _castVote(msg.sender, _proposalId, _proposalType, _support);
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
        Proposal storage proposal = (proposalType ? proposals[proposalId]: handlerProposals[proposalId]);
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
            emit VoteCast(voter, proposalId, support, votes);
        } else {
            emit HandlerVoteCast(voter, proposalId, support, votes);
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

    function judgeProposal(uint proposalID, bool proposalType) public {
        Proposal storage p = (proposalType ? proposals[proposalID]: handlerProposals[proposalID]);
        require(block.timestamp > p.endBlock, 'Proposal Ongoing');
         if((p.forVotes > p.againstVotes) || (p.minVotes > p.againstVotes)){
           if(proposalType){    //Approve Strategy
                strategies[p.strategy] = true;
                DAI.approve(p.strategy,uint(-1));
                p.executed = true;
           }else{   // Send DAI-wDAI LP Tokens to p.strategy
               IERC20 pair = IERC20(factory.getPair(address(DAI), address(WDAI)));
               uint bal = pair.balanceOf(address(this));
               pair.transfer(p.strategy,bal);
           }
        }else{
            p.canceled = true;
        }
    }

    function state(uint proposalId, bool proposalType) public view returns (ProposalState) {
        if(proposalType){
            require(proposalCount >= proposalId && proposalId > 0, "state: invalid proposal id");
        } else {
            require(handlerProposalCount >= proposalId && proposalId > 0, "state: invalid handler proposal id");
        }
        
        Proposal storage proposal = (proposalType ? proposals[proposalId]: handlerProposals[proposalId]);
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < proposal.minVotes) {
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