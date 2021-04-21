pragma solidity >0.4.13 <0.7.7;


import "./SafeMath.sol";
import "./strings.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "https://raw.githubusercontent.com/smartcontractkit/chainlink/develop/evm-contracts/src/v0.6/ChainlinkClient.sol";
pragma experimental ABIEncoderV2;
import "./uniswap/IUniswapV2Router02.sol";

/*

    Sports Book Contract for the Book Token Protocol created by 0xMesaj
    Rules for bets are scaled up by a factor of ten (i.e. a spread bet of +2.5 would be stored as 25)

*/

contract SportsBook is ChainlinkClient  {
    uint256 public ORACLE_PAYMENT = 1 * LINK;
    using strings for *;
    using SafeMath for uint256;
    
    event BetRequested(bytes32 betID,bytes16 betRef);
    event BetAccepted(bytes32 betID,uint256 odds);
    event BetPayout(bytes32 betID);
    event BetPush(bytes32 betID);
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

        uint256 odds;
        int256 rule;

        address creator;
    }

    struct Parlay{
        uint256 amount;
        uint256 timestamp;

        bytes32 odds;
        
        string[] indexes;
        string[] selections;
        int[] rules;
        address creator;
    }

    /* 
        Keeps track of money wagered in a market to assess risk
        for the Sports Book. Risk tolerance is a function of the
        DAI allowance the contract has from Treasury (Risks max 0.5% of total
        funding on each market).
    */
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
    mapping(uint256 => bool) public queriedIndexes;
    mapping(bytes32 => uint256) public queriedIDs;
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

    address oracle;
    address mesaj;
    bytes32 public betID;
    int256 MAX_BET;
    IERC20 dai;
    bool public isOperational;
    bool public freeFee;
    bool public noNewBets;
    IWETH weth;
    IUniswapV2Router02 immutable uniswapV2Router;
    address immutable treasury;

    constructor (IERC20 _DAI, IWETH _WETH, address _treasury, IUniswapV2Router02 _uniswapV2Router) public payable{ 
        setPublicChainlinkToken();

        mesaj = msg.sender;
        wards[mesaj] = true;
        treasury = _treasury;
        
        uniswapV2Router = _uniswapV2Router;
        isOperational = false;
        noNewBets = false;
        freeFee = false;
        oracle = 0x4dfFCF075d9972F743A2812632142Be64CA8B0EE;        //CHANGE
        dai = _DAI;
        weth = _WETH;
    }
    
    function resolveMatch( bytes32 _betID ) public {
        require(isOperational, 'Sports Book not active');
        Bet memory b = bets[_betID];
        require(_betID != 0x0, "Invalid Bet Reference");
        require(b.timestamp>matchCancellationTimestamp[b.index], 'Match is invalid');

        uint256 result = computeResult(b.index,b.selection,b.rule);
        //Win
        if( result == 1){
            uint256 amt = b.amount;
            uint256 odds = b.odds;
            address creator = b.creator;

            delete bets[_betID];
            uint256 winAmt = amt.mul(odds).div(100);
            dai.transfer(creator, winAmt);
            emit BetPayout(_betID);
        }
        //Push
        else if(result == 2){
            uint256 pushAmt = b.amount;
            address creator = b.creator;

            delete bets[_betID];
            dai.transferFrom(treasury,creator, pushAmt);
            emit BetPush(_betID);
        }
    }
    
    function resolveParlay( bytes32 _betID ) public {
        require(isOperational, 'Sports Book not active');
        Parlay memory p = parlays[_betID];
        require(_betID != 0x0, "Invalid Bet Reference");
        
        strings.slice memory o = bytes32ToString(p.odds).toSlice();
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1);
        
        bool win = true;
        for(uint i = 0; i < os.length; i++){
            uint ans = computeResult(bytesToUInt(stringToBytes32(p.indexes[i])),bytesToUInt(stringToBytes32(p.selections[i])), p.rules[i]);
            if(ans == 0){
                win = false;
            }
            //Leg of parlay pushed or cancelled, set the odds to 100 effectively nullifying that leg of parlay
            else if(ans == 2 || p.timestamp<matchCancellationTimestamp[uint256(stringToBytes32(p.indexes[i]))]){
                os[i] = '100'.toSlice();
            }
            else{
                os[i] = o.split(delim);
            }
        }     

        if(win){
            uint256 odds = calculateParlayOdds(os);
            uint256 amt = p.amount;
            address creator = p.creator;

            delete parlays[_betID];
            uint256 winAmt = amt.mul(odds).div(100);
            dai.transferFrom(treasury,creator, winAmt);
            emit BetPayout(_betID);
        }
    }
    
    /* Claim refund from declined bet */
    function claimRefund() external{
        require(isOperational, 'Sports Book not active');
        uint256 amt = refund[msg.sender];
        require(amt > 0, "No refund to claim");
        refund[msg.sender] = 0;
        dai.transferFrom(treasury,msg.sender,amt);
    }

    /* 
        Refund bet if match has a valid cancelation timestamp after the bet
        was placed - Used in cases of match cancellation/postponement
    */
    function refundBet( bytes32 _betID) external {
        require(isOperational, 'Sports Book not active');
        Bet memory b = bets[_betID];
        uint256 timestamp = matchCancellationTimestamp[b.index];
        if(b.timestamp < timestamp){
            uint256 amt = b.amount;
            address refundee = b.creator;
            delete bets[_betID];
            dai.transferFrom(treasury,refundee,amt);
            emit BetRejected(_betID);
        }
    }

    /*
        Every leg of the parlay must have a valid
        match cancellation timestamp greater than
        the bet placement timestamp to refund bet
    */
    function refundParlay( bytes32 _betID) external {
        require(isOperational, 'Sports Book not active');
        Parlay memory p = parlays[_betID];
        bool check = true;
        for(uint i=0;i<p.indexes.length;i++){
            uint256 timestamp = matchCancellationTimestamp[stringToUint(p.indexes[i])];
            if(p.timestamp > timestamp){
                check = false;
            }
        }
        if(check){
            uint256 amt = p.amount;
            address refundee = p.creator;
            delete bets[_betID];
            dai.transferFrom(treasury,refundee,amt);
            emit BetRejected(_betID);
        }
    }

    function bet(bytes16 _betRef, uint256 _index, uint256 _selection, uint256 _wagerAmt, int256 _rule, bool _payFeeWithLink ) public payable {
        require(isOperational, 'Sports Book not Operational');
        require(!noNewBets, 'Sports Book not accepting new wagers');
        /*
            Pay Oracle Fee With LINK, or with ETH which will
            be flash swapped into LINK
        */
        if(!freeFee){
            if(_payFeeWithLink){
                IERC20(LINK).transferFrom(msg.sender,address(this), ORACLE_PAYMENT);
            }else{
                uint256 preWETHBal = weth.balanceOf(address(this));
                weth.deposit{value : msg.value}();
                uint256 postWETHBal = weth.balanceOf(address(this));
                uint256 buyAmount = postWETHBal.sub(preWETHBal);
                address[] memory path = new address[](2);
                path[0] = address(weth);
                path[1] = address(LINK);
                uint256 preLinkBal = IERC20(LINK).balanceOf(address(this));
                uint256[] memory LINKamt = uniswapV2Router.swapExactTokensForTokens(buyAmount, 0, path, address(this), block.timestamp);
                uint256 postLinkBal = IERC20(LINK).balanceOf(address(this));
                uint256 purchasedLink = postLinkBal.sub(preLinkBal);
                require(purchasedLink > ORACLE_PAYMENT, "Insufficient ETH Sent to Pay Oracle");
            }
        }

        bytes32 _queryID = buildBet(_index, _selection, _rule);
        
        if(_queryID != 0x0){
            dai.transferFrom(msg.sender, address(treasury), _wagerAmt);
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
    }

    function betParlay( bytes16 _betRef,uint _amount, string memory _indexes, string memory _selections,  int[] memory _rules, bool _payFeeWithLink ) public payable{
        require(isOperational, 'Sports Book not Operational');
        require(!noNewBets, 'Sports Book not accepting new wagers');

        if(!freeFee){
            if(_payFeeWithLink){
                IERC20(LINK).transferFrom(msg.sender,address(this), ORACLE_PAYMENT);
            }else{  //Flash swap ETH to LINK
                uint256 preWETHBal = weth.balanceOf(address(this));
                weth.deposit{value : msg.value}();
                uint256 postWETHBal = weth.balanceOf(address(this));
                uint256 buyAmount = postWETHBal.sub(preWETHBal);
                address[] memory path = new address[](2);
                path[0] = address(weth);
                path[1] = address(LINK);
                uint256 preLinkBal = IERC20(LINK).balanceOf(address(this));
                uint256[] memory amountsBOOK = uniswapV2Router.swapExactTokensForTokens(buyAmount, 0, path, address(this), block.timestamp);
                uint256 postLinkBal = IERC20(LINK).balanceOf(address(this));
                uint256 purchasedLink = postLinkBal.sub(preLinkBal);
                require(purchasedLink > ORACLE_PAYMENT, "Insufficient ETH Sent to Pay Oracle");
            }
        }
     
        bytes32 _queryID = buildParlay(_indexes, _selections, _rules );

        if(_queryID != 0x0){
            dai.transferFrom(msg.sender, address(treasury), _wagerAmt);
            strings.slice memory s = _indexes.toSlice();
            strings.slice memory delim = ",".toSlice();
            string[] memory indexes = new string[](s.count(delim) + 1);

            require(indexes.length < 8, 'Parlay too large');

            for(uint i = 0; i < indexes.length; i++) {
                indexes[i] = s.split(delim).toString();
            }
            
            s =  _selections.toSlice();
            string[] memory selections = new string[](s.count(delim) + 1);
            for(uint i = 0; i < selections.length; i++) {
                selections[i] = s.split(delim).toString();
            }
                
            Parlay storage p = parlays[_queryID];
            p.creator = msg.sender;
            p.amount = _amount;
            p.indexes = indexes;
            p.selections = selections;
            p.rules = _rules;
            p.timestamp = block.timestamp;
        
            addressBets[p.creator].push(_queryID);
            emit BetRequested(_queryID, _betRef);
        }
    }

    /*
        Ward-Only Functions
    */

    // Only to be used to allow wards to delete faulty bets to protect sports book, 
    // returns wager amount to bet creator
    function deleteBet(bytes32 _betID, bool straight) public isWard(){
        if(straight){
            Bet memory b = bets[_betID];
            require(!matchResults[b.index].recorded, "Match already finalized - Cannot Delete Bet");
            uint256 amt = b.amount;
            address creator = b.creator;

            // If bet has odds, then we need to decrement sports
            // book risk when we delete bet
            if(b.odds > 0){
                uint256 riskToBeRemoved = (amt).mul(_odds).div(100);
                if(b.selection == 0){
                    sportsBookRisk[b.index].spreadDelta.outcome0Wagered = sportsBookRisk[b.index].spreadDelta.outcome0Wagered.sub(amt);
                    sportsBookRisk[b.index].spreadDelta.outcome0PotentialWin = sportsBookRisk[b.index].spreadDelta.outcome0PotentialWin.sub(riskToBeRemoved);
                }
                else if(b.selection == 1){
                    sportsBookRisk[b.index].spreadDelta.outcome1Wagered = sportsBookRisk[b.index].spreadDelta.outcome1Wagered.sub(amt);
                    sportsBookRisk[b.index].spreadDelta.outcome1PotentialWin = sportsBookRisk[b.index].spreadDelta.outcome1PotentialWin.sub(riskToBeRemoved);
                }
                else if(b.selection == 2){
                    sportsBookRisk[b.index].pointDelta.outcome0Wagered = sportsBookRisk[b.index].pointDelta.outcome0Wagered.sub(amt);
                    sportsBookRisk[b.index].pointDelta.outcome0PotentialWin = sportsBookRisk[b.index].pointDelta.outcome0PotentialWin.sub(riskToBeRemoved);
                }
                else if(b.selection == 3){
                    sportsBookRisk[b.index].pointDelta.outcome1Wagered = sportsBookRisk[b.index].pointDelta.outcome1Wagered.sub(amt);
                    sportsBookRisk[b.index].pointDelta.outcome1PotentialWin = sportsBookRisk[b.index].pointDelta.outcome1PotentialWin.sub(riskToBeRemoved);
                }
                else if(b.selection == 4){
                    sportsBookRisk[b.index].moneylineDelta.outcome0Wagered = sportsBookRisk[b.index].moneylineDelta.outcome0Wagered.sub(amt);
                    sportsBookRisk[b.index].moneylineDelta.outcome0PotentialWin = sportsBookRisk[b.index].moneylineDelta.outcome0PotentialWin.sub(riskToBeRemoved);
                }
                else if(b.selection == 5){
                    sportsBookRisk[b.index].moneylineDelta.outcome1Wagered = sportsBookRisk[b.index].moneylineDelta.outcome1Wagered.sub(amt);
                    sportsBookRisk[b.index].moneylineDelta.outcome1PotentialWin = sportsBookRisk[b.index].moneylineDelta.outcome1PotentialWin.sub(riskToBeRemoved);
                }
            }
            delete bets[_betID];
            dai.transferFrom(treasury,creator,amt);
        }else{
            Parlay memory p = parlays[_betID];
            for(uint i=0;i<p.indexes.length;i++){
                require(!matchResults[uint(stringToBytes32(p.indexes[i]))].recorded, "Match already finalized - Cannot Delete Parlay");
            }
            uint256 amt = p.amount;
            address creator = p.creator;
            delete parlays[_betID];
            dai.transferFrom(treasury,creator,amt);
        }
    }

    function setSportsBookState(bool state) public isWard(){
        isOperational = state;
    }

    function setNoNewBets(bool state) public isWard(){
        noNewBets = state;
    }

    function setWard(address appointee) public isWard(){
        require(!wards[appointee], "Appointee is already ward.");
        wards[appointee] = true;
    }

    function abdicate(address shame) public isWard(){
        require(mesaj != shame, "Et tu, Brute?");
        wards[shame] = false;
    }

    function setFeeState(bool isFree) public isWard(){
        freeFee = isFree;
    }

    function setOraclePayment(uint256 amt) public isWard(){
        ORACLE_PAYMENT = amt * LINK;
    }

    // Returns 1 for win, 2 for push
    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) internal view returns(uint win){
        MatchScores memory m = matchResults[_index];
        
        uint256 home_score = bytesToUInt(stringToBytes32(m.homeScore));
        uint256 away_score = bytesToUInt(stringToBytes32(m.awayScore));
        uint selection = _selection;
        int rule = _rule;   //rule is scaled up by 10 to deal with half points

        if(selection == 0){
            if( int(home_score*10)+rule > int(away_score*10) ){
                win = 1;
            }
            else if( int(home_score*10)+rule == int(away_score*10) ){
                win = 2;
            }
        }
        else if(selection == 1){
            if( (int(away_score*10)+rule) > int(home_score*10)){
                win = 1;
            }
            else if( (int(away_score*10)+rule) == int(home_score*10) ){
                win = 2;
            }
        }
        else if (selection == 2 ){
            if(int(home_score*10 + away_score*10) > rule){
                win = 1;
            }
            else if (int(home_score*10 + away_score*10) == rule){
                win = 2;
            }
        }
        else if(selection == 3){
           if(rule > int(home_score*10 + away_score*10)){
                win = 1;
            }
            else if (rule == int(home_score*10 + away_score*10)){
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

    /* 
        LINK Requesters:
        Final Score and Status Requesters are called externally, and odds
        requesters are called internally through bet and betParlay
     */
    function fetchFinalScore( uint256 _index ) public {
        require(!queriedIndexes[_index], "Index Already Queried");
        Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('9de0f2eae1104a248ddd327624360d7a'), address(this), this.fulfillScores.selector);
        req.add('type', 'score');
        req.addUint('index', _index);
        bytes32 _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
        queriedIDs[_queryID] = _index;
        queriedIndexes[_index] = true;
    }

    function checkMatchStatus ( uint256 _index ) public {
        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('7bbb3ac4ff634d67a0413f8540bf9af6'), address(this), this.fulfillStatus.selector);
        req.add('type', 'status');
        req.addUint('index', _index);
        bytes32 _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
        queriedStatus[_queryID] = _index;
    }

    function buildBet( uint256 _index, uint256 _selection, int256 _rule) internal returns (bytes32 _queryID){
        Chainlink.Request memory req =  buildChainlinkRequest(stringToBytes32('f24bb4144a0a40acb6e8fcf2d866cbeb'), address(this), this.fulfillBetOdds.selector);
        req.add('type', 'straight');
        req.addUint('index', _index);
        req.addUint('selection', _selection);
        req.addInt('rule', _rule);
        _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
    }
    
    function buildParlay(string memory _indexes, string memory _selections, int[] memory _rules) internal returns (bytes32 _queryID){
        string memory s;
        for(uint i = 0; i < _rules.length; i++){
            if(i!=0){
                s = s.toSlice().concat(','.toSlice());
            }
            s = s.toSlice().concat(intToString(_rules[i]).toSlice());
        }
        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('2a0c4bdfe815406eba8ecdee3cbcc2ee'), address(this), this.fulfillParlayOdds.selector);
        req.add('type', 'parlay');
        req.add('index', _indexes);
        req.add('selection', _selections);
        req.add('rule', s);
        _queryID = sendChainlinkRequestTo(oracle, req, ORACLE_PAYMENT);
    } 
    
    /* Oracle-Only Fulfillers  */
    function fulfillStatus(bytes32 _requestId, bool status) public isOracle() reco  rdChainlinkFulfillment(_requestId){
        uint256 index = queriedIDs[_requestId];
        if( status ){
            matchCancellationTimestamp[index] = block.timestamp;
        }
        delete queriedIDs[_requestId];
    }

    function fulfillParlayOdds(bytes32 _requestId, bytes32 _odds) public isOracle() recordChainlinkFulfillment(_requestId){
        Parlay storage p = parlays[_requestId];
        MAX_BET = int(dai.allowance(treasury,address(this)).mul(5).div(1000));   // 0.5% risk tolerance
        
        strings.slice memory s = bytes32ToString(_odds).toSlice();
        strings.slice memory delim = ".".toSlice();
        strings.slice[] memory odds = new strings.slice[](s.count(delim) + 1);
        for(uint i = 0; i < odds.length; i++) {
            odds[i] = s.split(delim);
        }
        uint256 aggregated_odds = calculateParlayOdds(odds);
        uint256 risk = p.amount.mul(aggregated_odds).div(100);
        require( uint(MAX_BET) > risk, "Parlay payout too large");
        p.odds = _odds;
        emit ParlayAccepted(_requestId,p.odds);
    }
    
    function fulfillBetOdds(bytes32 _requestId, uint256 _odds) public isOracle() recordChainlinkFulfillment(_requestId){
        MAX_BET = int(dai.allowance(treasury,address(this)).mul(5).div(1000));   // 0.5% risk tolerance

        Bet storage b = bets[_requestId];
        
        address creator = b.creator;
        uint256 amt = b.amount;
        uint256 potential = (amt).mul(_odds).div(100);

        Risk storage risk = sportsBookRisk[b.index];
        if(b.selection == 0){
            uint256 newPotential = safeAdd(potential,risk.spreadDelta.outcome0PotentialWin);
            int256 check = safeSub(newPotential,risk.spreadDelta.outcome1Wagered);
            if(check > MAX_BET || !(_odds>100)){
                delete bets[_requestId];
                refund[creator] = safeAdd(amt,refund[creator]);
                emit BetRejected(_requestId);
            }
            else{
                risk.spreadDelta.outcome0PotentialWin = newPotential;
                risk.spreadDelta.outcome0Wagered = safeAdd(amt,risk.spreadDelta.outcome0Wagered);
                b.odds = _odds;
                emit BetAccepted(_requestId,_odds);
            }
        }
        else if(b.selection == 1){
            int256 check = safeSub(risk.spreadDelta.outcome1PotentialWin.add(potential),risk.spreadDelta.outcome0Wagered);
            if(check > MAX_BET ||  !(_odds>100)){
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
            if(check > MAX_BET || !(_odds>100)){
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
            if(check > MAX_BET || !(_odds>100)){
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
            if(check > MAX_BET || !(_odds>100)){
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
            if(check > MAX_BET || !(_odds>100)){
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
        MatchScores storage m = matchResults[queriedIDs[_requestId]];
        m.homeScore = s.split(",".toSlice(), part).toString();
        m.awayScore = s.split(",".toSlice(), part).toString();
        m.recorded = true;
        queriedIndexes[queriedIDs[_requestId]] = false;
        delete queriedIDs[_requestId];
    }

    /* Utilities */
    function calculateParlayOdds(strings.slice[] memory o) internal view returns (uint256 odds){
        odds = 1;
        for(uint i=0;i < o.length; i++){
            if(i==0){
                odds = odds.mul(stringToUint(o[i].toString()));
            }
            else{
                odds = odds.mul(stringToUint(o[i].toString())).div(100);
            }
        }
    }

    function intToString(int i) internal pure returns (string memory){
        if (i == 0) return "0";
        bool negative = i < 0;
        uint j = uint(negative ? -i : i);
        uint l = j;
        uint len;
        while (j != 0){
            len++;
            j /= 10;
        }
        if (negative) ++len;
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (l != 0){
            bstr[k--] = byte(uint8(48 + l % 10));
            l /= 10;
        }
        if (negative) {
            bstr[0] = '-';
        }
        return string(bstr);
    }

    function stringToUint(string memory s) internal pure returns (uint result){
        bytes memory b = bytes(s);
        uint i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            uint c = uint(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
    }
    
    function safeSub(uint256 a, uint256 b) internal pure returns (int256){
        int256 c = int256(a - b);
        require( c <= int256(a), "Sorry, subtraction is hard...");
        return c;
    }

    function safeMultiply(uint256 b, int256 a) internal pure returns (uint256){
        if (a == 0) {return 0;}
        uint256 c = uint256(a) * b;
        require(c / uint256(a) == b, "Sorry, multiplication is hard...");
        return c;
    }
    
    function safeDivide(uint256 a, int256 b) internal pure returns (uint256){
        require(b > 0, "Sorry, division is hard...");
        uint256 c = a / uint256(b);
        return c;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256){
        uint256 c = a + b;
        require(c >= a, "Sorry, addition is hard...");
        return c;
    }

    function bytesToUInt(bytes32 v) internal pure returns (uint ret){
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
      
    function stringToBytes32(string memory source) internal pure returns (bytes32 result){
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
    
        assembly {
          result := mload(add(source, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory){
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