pragma solidity ^0.7.0;

import './SafeMath.sol';
import './strings.sol';
// import './OutcomeOracle.sol';
import './interfaces/IERC20.sol';
// import './ChainlinkClient.sol';

pragma experimental ABIEncoderV2;

/*
Sports Book Contract for the Book Token Protocol

Rules for bets are scaled up by a factor of ten (i.e. a spread bet of +2.5 would be stored as 25),
due to solidity not handling floating point numbers. Whenever we calculate with the rule, we use 
(rule/10) to get the true value

*/

contract SportsBook {
    // uint256 private ORACLE_PAYMENT = 1 * LINK;
    using strings for *;
    
    // OutcomeOracle public outcomeOracle;
    
    event BetRequested(bytes32 betID,bytes16 betRef);
    event BetAccepted(bytes32 betID,int256 odds);
    event LogNewProvableQuery(string description);
    
    struct MatchScores{
        uint256 homeScore;
        uint256 awayScore;
        bool recorded;
    }
    
    struct Bet{
        bytes16 betRef;
        uint256 index;
        address creator;
       
        int256 odds;
        uint256 selection;
        uint256 amount;
        int rule;
    }

    struct Parlay{
        bytes16 betRef;
        uint256 amount;
        string odds;
        address creator;
        
        string[] indexes;
        string[] selections;
        string[] rules;
    }

    struct Delta{
        int256 outcome0Wagered;
        int256 outcome0PotentialWin;
        int256 outcome1Wagered;
        int256 outcome1PotentialWin;
    }

    struct Risk{
        Delta spreadDelta;
        Delta pointDelta;
        Delta moneylineDelta;
    }

    

    mapping(uint256 => Risk) public sportsBookRisk;
    mapping(bytes16 => Parlay ) public parlayRef;
    mapping(bytes16 => Bet ) public betRef;
    mapping(bytes16 => Parlay ) public parlays;
    mapping(bytes16 => Bet ) public bets;
    mapping(uint => MatchScores) public matchResults;
    mapping(bytes32 => uint256) public queriedIndexes;
    
    mapping(address => bool) public wards;

    bytes32 public betID;
    int public odds;
    int256 MAX_BET = 100000;
    string oddsKey;
    IERC20 DAI;

    // constructor (IERC20 _DAI) public payable{

    constructor () public{      
        // outcomeOracle = new OutcomeOracle(this);
        // wards[msg.sender] = true;
        // setPublicChainlinkToken();
        // DAI = _DAI;
    }

    function updateOddsKey(string calldata _newKey) external {
        // require(wards[msg.sender]);
        oddsKey = _newKey;
    }
    
    
    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) internal view returns(int win){
        MatchScores memory m = matchResults[_index];
        
        uint256 home_score = m.homeScore;
        uint256 away_score = m.homeScore;
        uint selection = _selection;
        int rule = _rule;

        if(selection == 0){
            if( uint256(int256(home_score) + rule/10) > away_score){
                win = 1;
            }
            else if( uint256(int256(home_score) + rule/10) == away_score ){
                win = 2;
            }
        }
        else if(selection == 1){
            if(uint256(int256(away_score) + rule/10) > home_score){
                win = 1;
            }
            else if(uint256(int256(away_score) + rule/10) == home_score){
                win = 2;
            }
        }
        else if (selection == 2 ){
            if((home_score + away_score > uint256(rule/10))){
                win = 1;
            }
            else if (home_score + away_score == uint256(rule/10)){
                win = 2;
            }
        }
        else if(selection == 3){
            if((uint256(rule/10) > home_score + away_score)){
                win = 1;
            }
            else if (uint256(rule/10) == home_score + away_score){
                win = 2;
            }
        }
        else if(selection == 4 ){
            if((home_score > away_score)){
                win = 1;
            }
            else if (home_score == away_score){
                win = 2;
            }
        }
        else if (selection == 5 ){
            if(away_score > home_score){
                  win = 1;
            }
            else if(away_score == home_score){
                  win = 2;
            }
        }
    }
    
    function resolveMatch( bytes16 _betRef ) public {
        Bet memory b = bets[_betRef];
        require(matchResults[b.index].recorded , "Match Result not known");

        if(computeResult(b.index,b.selection,b.rule) == 1){
            //transfer win amount to b.creator
            if (b.odds > 0) {
                DAI.transfer(b.creator, safeMultiply(b.amount,b.odds/100));
            }
            else{
                DAI.transfer(b.creator, safeDivide(b.amount,(b.odds/-100)));
            }
        }
    }
    
    function calculateParlayOdds(string memory _o) internal view returns (int256 odds){
        strings.slice memory o = _o.toSlice();
        strings.slice memory delim = ",".toSlice();
        string[] memory os = new string[](o.count(delim) + 1);
        for(uint i=0;i < os.length; i++){
            odds += int256(stringToBytes32(os[i]));
        }
        return(odds > 2 ? (odds-1)*100 : (-100)/(odds-1));
    }
    
    function resolveParlay( bytes16 _betRef ) public {
        Parlay memory p = parlays[_betRef];
        require(p.creator != address(0x0), "Invalid Bet Reference");
        
        strings.slice memory o = p.odds.toSlice();
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1);
        
        bool win = true;
        for(uint i = 0; i < p.indexes.length; i++){
            int ans = computeResult(uint256(stringToBytes32(p.indexes[i])),uint256(stringToBytes32(p.selections[i])), int256(stringToBytes32(p.rules[i])));
            if(ans == 0){
                win = false;
            }
            else if(ans == 2){
                os[i] = '100'.toSlice();
            }
        }
        string memory odds = strings.join(','.toSlice(),os);
        if(win){
            int256 _odds = calculateParlayOdds(odds);
            if (_odds > 0) {
                DAI.transfer(p.creator, safeMultiply(p.amount, _odds/100));
            }
            else{
                DAI.transfer(p.creator,  safeDivide(p.amount,_odds/-100));
            }
        }
    }
    
    function fetchFinalScore( string memory _index, bytes16 betRef ) public {
        Bet b = bets[_betID];
        Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('9de0f2eae1104a248ddd327624360d7a'), address(this), this.fulfillScores.selector);
        req.add("type", 'score');
        req.addUint('index', _index);
        _queryID = sendChainlinkRequestTo(0x4dfFCF075d9972F743A2812632142Be64CA8B0EE, req, ORACLE_PAYMENT);
        queriedIndexes[_queryID] = _index;
    }
    
    function recordScore(uint _index, uint256 _homeScore, uint256 _awayScore) public  {
        // require(msg.sender == address(outcomeOracle), "Only the Outcome Oracle has permission to record match results...");
        MatchScores storage m = matchResults[_index];
        m.homeScore = _homeScore;
        m.awayScore = _awayScore;
        m.recorded = true;
    }

    function buildBet( uint256 _index, uint256 _selection, int256 _rule) internal returns (bytes32 _queryID){
        // Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('8b47ea9ea0594c4e9ec88f616abd57b9'), address(this), this.fulfillBetOdds.selector);
        // req.add("type", 'straight');
        // req.addUint('index', _index);
        // req.addUint('selection', _selection);
        // req.addInt('rule', _rule);
        // _queryID = sendChainlinkRequestTo(0x4dfFCF075d9972F743A2812632142Be64CA8B0EE, req, ORACLE_PAYMENT);
    }
    
    function buildParlay(string memory _indexes, string memory _selections, string memory _rules) internal returns (bytes32 _queryID){
        // Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('8b47ea9ea0594c4e9ec88f616abd57b9'), address(this), this.fulfillParlayOdds.selector);
        // req.add('type', 'parlay');
        // req.add('index', _indexes);
        // req.add('selection', _selections);
        // req.add('rule', _rules);
        // _queryID = sendChainlinkRequestTo(0x4dfFCF075d9972F743A2812632142Be64CA8B0EE, req, ORACLE_PAYMENT);
    }

    function fulfillScores(bytes32 _requestId, bytes32 memory score) public recordChainlinkFulfillment(_requestId){
        MatchScores m = matchResults[queriedIndexes[_requestId]];
        m.homeScore = bytes32ToString(score).toSlice().toString();
        m.awayScore = bytes32ToString(score).toSlice().split(",".toSlice()).toString();
        delete queriedIndexes[_requestId];
    }
    
    function fulfillBetOdds(bytes32 _requestId, int256 _odds)public recordChainlinkFulfillment(_requestId){
        // emit RequestEthereumPriceFulfilled(_requestId, _price);
        odds = _odds;
        Bet storage b = bets[_requestId];
        if(_odds > 0){
            uint256 potential = safeMultiply(amount, safeDivide(_odds, 100));
        }
        else{
            uint256 potential = safeDivide(amount, safeDivide(_odds, -100));
        }
        Risk risk = sportsBookRisk[b.index];
        if(b.selection == 0){
            risk.spreadDelta.outcome0PotentialWin += potential;
            risk.spreadDelta.outcome0Wagered += b.amount;
            if(risk.spreadDelta.outcome0PotentialWin-risk.spreadDelta.outcome1Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }
        else if(b.selection == 1){
            risk.spreadDelta.outcome1PotentialWin += potential;
            risk.spreadDelta.outcome1Wagered += b.amount;
            if(risk.spreadDelta.outcome1PotentialWin-risk.spreadDelta.outcome0Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }
        else if(b.selection == 2){
            risk.pointDelta.outcome0PotentialWin += potential;
            risk.pointDelta.outcome0Wagered += b.amount;
            if(risk.spreadDelta.outcome0PotentialWin-risk.spreadDelta.outcome1Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }
        else if(b.selection == 3){
            risk.pointDelta.outcome1PotentialWin += potential;
            risk.pointDelta.outcome1Wagered += b.amount;
            if(risk.spreadDelta.outcome1PotentialWin-risk.spreadDelta.outcome0Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }
        else if(b.selection == 4){
            risk.moneylineDelta.outcome0PotentialWin += potential;
            risk.moneylineDelta.outcome0Wagered += b.amount;
            if(risk.spreadDelta.outcome0PotentialWin-risk.spreadDelta.outcome1Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }
        else if(b.selection == 5){
            risk.moneylineDelta.outcome1PotentialWin += potential;
            risk.moneylineDelta.outcome1Wagered += b.amount;
            if(risk.spreadDelta.outcome1PotentialWin-risk.spreadDelta.outcome0Wagered > MAX_BET){
                delete b;
                DAI.transfer(b.creator, b.amount);
                // DAI.transferFrom( TREASURY , b.creator, b.amount);
            }
        }

        b.odds = odds;
        emit BetAccepted(_requestId,odds);
    }
     
    // function fulfillParlayOdds(bytes32 _requestId, string memory _odds)public recordChainlinkFulfillment(_requestId){
    //     Parlay storage p = parlays[_requestId];
    //     p.odds = _odds;
    //     emit BetAccepted(_requestId,odds);
    // }


    function bet(bytes16 _betRef, uint256 _index, uint256 _selection, uint256 _wagerAmt, int256 _rule ) public {
        bytes32 _queryID = buildBet(_index, _selection, _rule);
        betID = _queryID;
        
        if(betID != 0x0){
            DAI.transferFrom(msg.sender,address(this),_wagerAmt);
        }
        
        Bet storage b = betRef[_betRef];
        b.betRef = _betRef;
        b.creator = msg.sender;
        b.index = _index;
        b.amount = _wagerAmt;
        b.selection = _selection;
        b.rule = _rule;
        
        bets[_betRef] = b;
        
        emit BetRequested(_queryID, _betRef);
    }

    function betParlay(bytes16 _betRef,uint _amount, string memory _indexes, string memory _selections, string memory _rules) public{
        bytes32 _queryID = buildParlay(_indexes, _selections, _rules );
        betID = _queryID;
        
        if(betID != 0x0){
        DAI.transferFrom(msg.sender,address(this),_amount);
        }
        
        strings.slice memory s = _indexes.toSlice();
        strings.slice memory delim = ",".toSlice();
        string[] memory indexes = new string[](s.count(delim) + 1);
        for(uint i = 0; i < indexes.length; i++) {
           indexes[i] = s.split(delim).toString();
        }
        
        s =  _selections.toSlice();
        string[] memory selections = new string[](s.count(delim) + 1);
        for(uint i = 0; i < selections.length; i++) {
           selections[i] = s.split(delim).toString();
        }
        
        s =  _rules.toSlice();
        string[] memory rules = new string[](s.count(delim) + 1);
        for(uint i = 0; i < rules.length; i++) {
           rules[i] = s.split(delim).toString();
        }
        
        Parlay storage p = parlayRef[_betRef];
        p.creator = msg.sender;
        p.amount = _amount;
        p.indexes = indexes;
        p.selections = selections;
        p.rules = rules;
        p.betRef = _betRef;

        parlays[_betRef] = p;

        emit BetRequested(_queryID, _betRef);
    }
    
    function safeMultiply(uint256 b, int256 a) internal pure returns (uint256) {
        if (a == 0) {return 0;}
        uint256 c = uint256(a) * b;
        require(c / uint256(a) == b, "Multiplication Error");
        return c;
    }
    
    
    function safeDivide(uint256 a, int256 b) internal pure returns (uint256) {
        require(b > 0, "Bad Division");
        uint256 c = a / uint256(b);
        return c;
    }
      
    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
    
        assembly { // solhint-disable-line no-inline-assembly
          result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

}