pragma solidity >0.4.13 <0.7.7;


import "./SafeMath.sol";
import "./strings.sol";
import "./IERC20.sol";
// import "chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "https://raw.githubusercontent.com/smartcontractkit/chainlink/develop/evm-contracts/src/v0.6/ChainlinkClient.sol";
pragma experimental ABIEncoderV2;


/*

Sports Book Contract for the Book Token Protocol created by 0xMesaj

Rules for bets are scaled up by a factor of ten (i.e. a spread bet of +2.5 would be stored as 25),
due to solidity not handling floating point numbers

*/

contract SportsBook is ChainlinkClient  {
    uint256 private ORACLE_PAYMENT = 1 * LINK;
    using strings for *;
    using SafeMath for uint256;
    
    event BetRequested(bytes32 betID,bytes16 betRef);
    event BetAccepted(bytes32 betID,int256 odds);
    event BetRejected(bytes32 betID);
    event ParlayAccepted(bytes32 betID,bytes32 odds);
    
    struct MatchScores{
        string homeScore;
        string awayScore;
        bool recorded;
    }
    
    struct Bet{
        uint256 index;
        uint256 timestamp;
        uint256 selection;
        uint256 amount;
        int256 odds;
       
        int rule;
        address creator;
        
        
        
    }

    struct Parlay{
        uint256 amount;
        uint256 timestamp;
        bytes32 odds;
        
        address creator;
        
        string[] indexes;
        string[] selections;
        string[] rules;
    }

    struct Delta{
        uint256 outcome0Wagered;
        uint256 outcome0PotentialWin;
        uint256 outcome1Wagered;
        uint256 outcome1PotentialWin;
    }

    struct Risk{
        Delta spreadDelta;
        Delta pointDelta;
        Delta moneylineDelta;
    }

    mapping(uint256 => Risk) public sportsBookRisk;
    mapping(bytes32 => Parlay ) public parlays;
    mapping(bytes32 => Bet ) public bets;
    mapping(uint => MatchScores) public matchResults;
    mapping(address => uint) public refund;
    mapping(uint256 => uint256) public matchCancellationTimestamp;
    mapping(bytes32 => uint256) public queriedIndexes;
    mapping(bytes32 => uint256) public queriedStatus;
    mapping(address => bool) public wards;
    mapping(address => bytes32[]) public addressBets;

    modifier isWard(){
        require (wards[msg.sender], "Error: Wards only");
        _;
    }

    modifier isOracle(){
        require (msg.sender == oracle , "Error: Oracle only");
        _;
    }

    address treasury;
    address oracle;
    address mesaj;
    bytes32 public betID;
    uint256 MAX_BET;
    IERC20 dai;
    bool allowWagers = false;


    // constructor (IERC20 _DAI, address _treasury) public payable{ 
    constructor (IERC20 _DAI) public payable{ 
        // treasury = _treasury;
        mesaj = msg.sender;
        wards[mesaj] = true;
        setPublicChainlinkToken();
        // MAX_BET = _DAI.allowance(treasury,address(this));
        
        oracle = 0x4dfFCF075d9972F743A2812632142Be64CA8B0EE;
        dai = _DAI;
    }
    
    function resolveMatch( bytes32 _betID ) public {
        Bet memory b = bets[_betID];
        require(_betID != 0x0, "Invalid Bet Reference");
        require(b.timestamp>matchCancellationTimestamp[b.index], 'Match is invalid');

        if(computeResult(b.index,b.selection,b.rule) == 1){
            uint256 amt = b.amount;
            int256 odds = b.odds;
            address creator = b.creator;

            //transfer win amount to b.creator
            if (odds > 0) {
                delete bets[_betID];
                uint256 winAmt = safeMultiply(amt,odds)/100;
                dai.transfer(creator, winAmt);
            }
            else{
                delete bets[_betID];
                uint winAmt = safeDivide(amt,-1*odds)/100;
                dai.transfer(b.creator, winAmt);
            }
        }
    }
    
    function resolveParlay( bytes32 _betID ) public {
        Parlay memory p = parlays[_betID];
        require(_betID != 0x0, "Invalid Bet Reference");
        
        strings.slice memory o = bytes32ToString(p.odds).toSlice();
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1);
        
        bool win = true;
        for(uint i = 0; i < p.indexes.length; i++){
            int ans = computeResult(uint256(stringToBytes32(p.indexes[i])),uint256(stringToBytes32(p.selections[i])), int256(stringToBytes32(p.rules[i])));
            if(ans == 0){
                win = false;
            }
            else if(ans == 2 || p.timestamp>matchCancellationTimestamp[uint256(stringToBytes32(p.indexes[i]))]){
                os[i] = '100'.toSlice();
            }
        }     
        if(win){
            int256 odds = calculateParlayOdds(strings.join(','.toSlice(),os));
            uint256 amt = p.amount;
            address creator = p.creator;

            if (odds > 0) {
                delete parlays[_betID];
                dai.transfer(creator, safeMultiply(amt,odds)/100);
            }
            else{
                delete parlays[_betID];
                dai.transfer(creator, safeDivide(amt,(-1*odds)/-100));
            }
        }
    }
    
    /* Claim refund from declined bet */
    function claimRefund() external{
        uint256 amt = refund[msg.sender];
        require(amt > 0, "No refund to claim");
        refund[msg.sender] = 0;
        // dai.transferFrom(treasury,msg.sender,amt);
        dai.transfer(msg.sender,amt);
    }

    /* 
        Refund bet if match has a valid cancelation timestamp after the bet
        was placed - Used in cases of match cancellation/postponement
     */
    function refundBet( bytes32 _betID) external {
        Bet memory b = bets[_betID];
        uint256 timestamp = matchCancellationTimestamp[b.index];
        if(b.timestamp < timestamp){
            uint256 amt = b.amount;
            address refundee = b.creator;
            delete bets[_betID];
            // dai.transferFrom(treasury,refundee,amt);
            dai.transfer(msg.sender,amt);
        }
    }
    
    function bet(bytes16 _betRef, uint256 _index, uint256 _selection, uint256 _wagerAmt, int256 _rule ) public {
        require(allowWagers, 'Sports Book not currently accepting wagers');
        bytes32 _queryID = buildBet(_index, _selection, _rule);
        
        if(_queryID != 0x0){
            dai.transferFrom(msg.sender,address(this),_wagerAmt);
        }
        
        Bet storage b = bets[_queryID];
        b.creator = msg.sender;
        b.index = _index;
        b.amount = _wagerAmt;
        b.selection = _selection;
        b.rule = _rule;
        b.timestamp = block.timestamp;
        
        addressBets[b.creator].push(_queryID);
        emit BetRequested(_queryID, _betRef);
    }

    function betParlay(bytes16 _betRef,uint _amount, string memory _indexes, string memory _selections, string memory _rules) public {
        require(allowWagers, 'Sports Book not currently accepting wagers');
        bytes32 _queryID = buildParlay(_indexes, _selections, _rules );

        if(_queryID != 0x0){
            dai.transferFrom(msg.sender,address(this),_amount);
        }
        
        strings.slice memory s = _indexes.toSlice();
        strings.slice memory delim = ",".toSlice();
        string[] memory indexes = new string[](s.count(delim) + 1);

        require(indexes.length < 6, 'Parlay too large');

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
        
        Parlay storage p = parlays[_queryID];
        p.creator = msg.sender;
        p.amount = _amount;
        p.indexes = indexes;
        p.selections = selections;
        p.rules = rules;
        p.timestamp = block.timestamp;
    
        addressBets[p.creator].push(_queryID);
        emit BetRequested(_queryID, _betRef);
    }

    /* 
        Only to be used to allow wards to delete faulty bets to protect sports book, 
        returns wager amt to bet creator. Wards have no incentive to abuse this authority
        as if it is ever misused, bettors will simply stop using the sports book
    */
    function deleteBet(bytes32 _betID, bool straight) public isWard() {
        if(straight){
            Bet memory b = bets[_betID];
            require(!matchResults[b.index].recorded, "Match already finalized - Cannot Delete Bet");
            uint256 amt = b.amount;
            address creator = b.creator;
            delete bets[_betID];
            // dai.transferFrom(treasury,creator,amt);
            dai.transfer(msg.sender,amt);
        }else{
            Parlay memory p = parlays[_betID];
            for(uint i=0;i<p.indexes.length;i++){
                require(!matchResults[uint(stringToBytes32(p.indexes[i]))].recorded, "Match already finalized - Cannot Delete Bet");
            }
            uint256 amt = p.amount;
            address creator = p.creator; 
            delete parlays[_betID];
            // dai.transferFrom(treasury,creator,amt);
            dai.transfer(msg.sender,amt);
        }
    }

    function setSportsBookState(bool state) public isWard(){
        allowWagers = state;
    }

    function setWard(address appointee) public isWard(){
        require(!wards[appointee], "Appointee is already ward.");
        wards[appointee] = true;
    }

    function abdicate(address shame) public isWard(){
        require(mesaj != shame, "Et tu, Brute?");
        wards[shame] = false;
    }

    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) internal view returns(int win){
        MatchScores memory m = matchResults[_index];
        
        uint256 home_score = bytesToUInt(stringToBytes32(m.homeScore));
        uint256 away_score = bytesToUInt(stringToBytes32(m.homeScore));
        uint selection = _selection;
        int rule = _rule;

        if(selection == 0){
              if( int(home_score.mul(10))+rule > int(away_score.mul(10)) ){
                win = 1;
            }
            else if( int(home_score.mul(10)) + rule == int(away_score.mul(10)) ){
                win = 2;
            }
        }
        else if(selection == 1){
            if( (int(away_score.mul(10))+rule) > int(home_score.mul(10))){
                win = 1;
            }
            else if( (int(away_score.mul(10))+rule) == int(home_score.mul(10)) ){
                win = 2;
            }
        }
        else if (selection == 2 ){
            if(int((home_score.mul(10)) + (away_score.mul(10))) > rule){
                win = 1;
            }
            else if (int((home_score.mul(10)) + (away_score.mul(10))) == rule){
                win = 2;
            }
        }
        else if(selection == 3){
            if(rule > int(home_score.mul(10) + away_score.mul(10))){
                win = 1;
            }
            else if (rule == int(home_score.mul(10) + away_score.mul(10))){
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

    /* Requesters */
    function fetchFinalScore( uint256 _index ) public {
        Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('9de0f2eae1104a248ddd327624360d7a'), address(this), this.fulfillScores.selector);
        req.add('type', 'score');
        req.addUint('index', _index);
        bytes32 _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
        queriedIndexes[_queryID] = _index;
    }

    function checkMatchStatus ( uint256 _index ) public {
        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('7bbb3ac4ff634d67a0413f8540bf9af6'), address(this), this.fulfillStatus.selector);
        req.add('type', 'status');
        req.addUint('index', _index);
        bytes32 _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
        queriedStatus[_queryID] = _index;
    }

    function buildBet( uint256 _index, uint256 _selection, int256 _rule) internal returns (bytes32 _queryID){
        Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('8b47ea9ea0594c4e9ec88f616abd57b9'), address(this), this.fulfillBetOdds.selector);
        req.add('type', 'straight');
        req.addUint('index', _index);
        req.addUint('selection', _selection);
        req.addInt('rule', _rule);
        _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
    }
    
    function buildParlay(string memory _indexes, string memory _selections, string memory _rules) internal returns (bytes32 _queryID){
        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('2a0c4bdfe815406eba8ecdee3cbcc2ee'), address(this), this.fulfillParlayOdds.selector);
        req.add('type', 'parlay');
        req.add('index', _indexes);
        req.add('selection', _selections);
        req.add('rule', _rules);
        _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
    } 
    
    /* Fulfillers */
    function fulfillStatus(bytes32 _requestId, bool status) public isOracle() {
        uint256 index = queriedIndexes[_requestId];
        if( status ){
            matchCancellationTimestamp[index] = block.timestamp;
        }
        delete queriedIndexes[_requestId];
    }

    function fulfillParlayOdds(bytes32 _requestId, bytes32 _odds) public isOracle() recordChainlinkFulfillment(_requestId){
        Parlay storage p = parlays[_requestId];
        MAX_BET = dai.balanceOf(address(this)) - p.amount;
        p.odds = _odds;
        emit ParlayAccepted(_requestId,p.odds);
    }

    function fulfillBetOdds(bytes32 _requestId, int256 _odds) public isOracle() recordChainlinkFulfillment(_requestId){
        // MAX_BET = dai.allowance(treasury,address(this));
        
        Bet storage b = bets[_requestId];
        
        address creator = b.creator;
        uint256 amt = b.amount;
        uint256 potential = 0;
        MAX_BET = dai.balanceOf(address(this)) - amt;
        
        potential = (_odds > 0 ? safeMultiply(amt,_odds)/100 : safeDivide(amt,-1*_odds)*100);
        Risk storage risk = sportsBookRisk[b.index];
        if(b.selection == 0){
            int256 check = safeSub(risk.spreadDelta.outcome0PotentialWin.add(potential),risk.spreadDelta.outcome1Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.spreadDelta.outcome0PotentialWin = potential.add(risk.spreadDelta.outcome0PotentialWin);
                risk.spreadDelta.outcome0Wagered = safeAdd(amt,risk.spreadDelta.outcome0Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 1){
            int256 check = safeSub(risk.spreadDelta.outcome1PotentialWin.add(potential),risk.spreadDelta.outcome0Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.spreadDelta.outcome1PotentialWin = safeAdd(potential,risk.spreadDelta.outcome1PotentialWin);
                risk.spreadDelta.outcome1Wagered = safeAdd(amt,risk.spreadDelta.outcome1Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 2){
            int256 check = safeSub(risk.pointDelta.outcome0PotentialWin.add(potential),risk.pointDelta.outcome1Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.pointDelta.outcome0PotentialWin = safeAdd(potential,risk.pointDelta.outcome0PotentialWin);
                risk.pointDelta.outcome0Wagered = safeAdd(amt,risk.pointDelta.outcome0Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 3){
            int256 check = safeSub(risk.pointDelta.outcome1PotentialWin.add(potential),risk.pointDelta.outcome0Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.pointDelta.outcome1PotentialWin = safeAdd(potential,risk.pointDelta.outcome1PotentialWin);
                risk.pointDelta.outcome1Wagered = safeAdd(amt,risk.pointDelta.outcome1Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 4){
            int256 check = safeSub(risk.moneylineDelta.outcome0PotentialWin.add(potential),risk.moneylineDelta.outcome1Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.moneylineDelta.outcome0PotentialWin = safeAdd(potential,risk.moneylineDelta.outcome0PotentialWin);
                risk.moneylineDelta.outcome0Wagered = safeAdd(amt,risk.moneylineDelta.outcome0Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 5){
            int256 check = safeSub(risk.moneylineDelta.outcome1PotentialWin.add(potential),risk.moneylineDelta.outcome0Wagered);
            if(check > int(MAX_BET) || (_odds<100 && _odds>-100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.moneylineDelta.outcome1PotentialWin = safeAdd(potential,risk.moneylineDelta.outcome1PotentialWin);
                risk.moneylineDelta.outcome1Wagered = safeAdd(amt,risk.moneylineDelta.outcome1Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
    }
    
    function fulfillScores(bytes32 _requestId, bytes32 score) public isOracle() recordChainlinkFulfillment(_requestId){
        require(score != 0x0, "Invalid Response");
        strings.slice memory s = bytes32ToString(score).toSlice();
        strings.slice memory part;
        MatchScores storage m = matchResults[queriedIndexes[_requestId]];
        m.homeScore = s.split(",".toSlice(), part).toString();
        m.awayScore = s.split(",".toSlice(), part).toString();
        m.recorded = true;
        
        delete queriedIndexes[_requestId];
    }

    /* Utilities */
     function calculateParlayOdds(string memory _o) internal pure returns (int256 odds){
        strings.slice memory o = _o.toSlice();
        strings.slice memory delim = ",".toSlice();
        string[] memory os = new string[](o.count(delim) + 1);
        for(uint i=0;i < os.length; i++){
            odds += int256(stringToBytes32(os[i]));
        }
        return(odds > 2 ? (odds-1)*100 : (-100)/(odds-1));
    }
    
    function safeSub(uint256 a, uint256 b) internal pure returns (int256) {
        int256 c = int(a - b);
        require( c < int(a), "Sorry, subtraction is hard...");
        return c;
    }

    function safeMultiply(uint256 b, int256 a) internal pure returns (uint256) {
        if (a == 0) {return 0;}
        uint256 c = uint256(a) * b;
        require(c / uint256(a) == b, "Sorry, multiplication is hard...");
        return c;
    }
    
    function safeDivide(uint256 a, int256 b) internal pure returns (uint256) {
        require(b > 0, "Sorry, division is hard...");
        uint256 c = a / uint256(b);
        return c;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "Sorry, addition is hard...");
        return c;
    }

    function bytesToUInt(bytes32 v) internal pure returns (uint ret) {
        if (v == 0x0) {
            revert();
        }
        uint digit;
        for (uint i = 0; i < 32; i++) {
            digit = uint((uint(v) / (2 ** (8 * (31 - i)))) & 0xff);
            if (digit == 0) {
                break;
            }
            else if (digit < 48 || digit > 57) {
                revert();
            }
            ret *= 10;
            ret += (digit - 48);
        }
        return ret;
    }
      
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
    
        assembly { // solhint-disable-line no-inline-assembly
          result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
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