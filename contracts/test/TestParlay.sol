pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import "../strings.sol";
import "./TestToken.sol";
import "../SafeMath6.sol";

import 'hardhat/console.sol';

contract TestParlay{
    using strings for *;
    using SafeMath for uint256;
      
    bool public complete = false;
    bool public isOperational = true;
    int256 public ans = 0;
    uint256 public len = 0;
    strings.slice[] public test;
    TestToken dai;
    uint256 public testValue;
 mapping(uint256 => bool) public banned;
    struct MatchScores{
        string homeScore;
        string awayScore;
        uint256 recorded;
    }

    struct Parlay{
        uint256 amount;
        uint256 timestamp;

        bytes32 odds;
        
        string[] indexes;
        string[] selections;
        int[] rules;

        bytes16 betRef;

        address creator;
    }

    mapping(bytes16 => Parlay ) public parlays;
    mapping(uint => MatchScores) public matchResults;
    mapping(uint256 => uint256) public matchCancellationTimestamp;

    constructor(TestToken _dai) public{
        dai = _dai;
        dai.mint(address(this),12300000000);
 
    }

     function betParlay( bytes16 _betRef,uint _wagerAmt, string memory _indexes, string memory _selections,  int[] memory _rules ) public payable{
        require(isOperational, 'Sports Book not Operational');
        require(address(parlays[_betRef].creator) == address(0x0), 'Are you malicious or are you unlucky?');
     
        // bytes32 _queryID = buildParlay( _indexes, _selections, _rules, _wagerAmt );

        // if(_queryID != 0x0){
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
                if(banned[uint256(stringToBytes32(selections[i]))]){
                    revert("Sports Book not accepting wagers for specified Game ID");
                }
                selections[i] = s.split(delim).toString();
            }
                
            Parlay storage p = parlays[_betRef];
            p.creator = msg.sender;
            p.amount = _wagerAmt;
            p.indexes = indexes;
            p.selections = selections;
            p.rules = _rules;
            p.timestamp = 1621744651;
            p.betRef = _betRef;
            p.odds = 0x3134352c31393100000000000000000000000000000000000000000000000000;
            // p.odds = 0x0;

            MatchScores storage m = matchResults[16588];
            m.homeScore = '150';
            m.awayScore = '100';
            m.recorded = 1621744652;
            matchCancellationTimestamp[16588] = 1621744653;
            matchCancellationTimestamp[16589] = 1621744653;
    }

    /*
        Every leg of the parlay must have a valid
        match cancellation timestamp greater than
        the bet placement timestamp to refund bet
        or if 5 minutes have passed and the parlay
        has not received valid odds
    */
    function refundParlay( bytes16 _betRef) external {
        require(isOperational, 'Sports Book not active');
        Parlay memory p = parlays[_betRef];
        uint256 current = block.timestamp;

        if((p.timestamp + 300) < current && p.odds == bytes32(0)){
            uint256 amt = p.amount;
            address refundee = p.creator;
            delete parlays[_betRef];

            // dai.transferFrom(treasury,refundee,amt);
            // emit BetRefunded(_betRef);
        }
        else{
            for(uint i=0;i<p.indexes.length;i++){
                uint256 timestamp = matchCancellationTimestamp[stringToUint(p.indexes[i])];
                if(p.timestamp > timestamp){
                    revert("Parlay has valid legs");
                }
            }
            uint256 amt = p.amount;
            address refundee = p.creator;
            delete parlays[_betRef];
            // dai.transferFrom(treasury,refundee,amt);
            // emit BetRefunded(_betRef);
        }
    }

    function resolveParlay( bytes16 _betRef ) public {
        require(isOperational, 'Sports Book not active');
        Parlay memory p = parlays[_betRef];
        require(_betRef != 0x0, "Invalid Bet Reference");
        
        
        strings.slice memory o = bytes32ToString(p.odds).toSlice();
        strings.slice memory delim = ",".toSlice();
        uint256 count = o.count(delim) + 1;
        strings.slice[] memory os = new strings.slice[](count); 
        bool win = true;
        for(uint i = 0; i < count; i++){
            require(matchResults[bytesToUInt(stringToBytes32(p.indexes[i]))].recorded + 604800 > block.timestamp, "Match Results only valid for 1 week");
            
            uint256 ans = computeResult(bytesToUInt(stringToBytes32(p.indexes[i])),bytesToUInt(stringToBytes32(p.selections[i])), p.rules[i]);

            if(ans == 0){
                win = false;
            }
            // Leg of parlay pushed or cancelled, set the odds to 100 effectively nullifying that leg of parlay
            else if(ans == 2 || p.timestamp<matchCancellationTimestamp[bytesToUInt(stringToBytes32(p.indexes[i]))]){
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

            delete parlays[_betRef];
            uint256 winAmt = amt.mul(odds).div(100);
            console.log("winAmt=");
            console.log(winAmt);
            // dai.transferFrom(address(this),creator, winAmt);
        }
    }

    function testLook(bytes16 ref,uint256 check) public{
        testValue = bytesToUInt(stringToBytes32(parlays[ref].indexes[check]));
    }


   // Returns 1 for win, 2 for push
    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) public returns(uint256 win){
        MatchScores memory m = matchResults[_index];
        // console.log("_index");
        // console.logUint(_index);
        // console.log("_selection");
        // console.logUint(_selection);
        // console.log("_rule");
        // console.logInt(_rule);
        
        uint256 home_score = bytesToUInt(stringToBytes32(m.homeScore));
        uint256 away_score = bytesToUInt(stringToBytes32(m.awayScore));
        uint256 selection = _selection;
        int256 rule = _rule;   //rule is scaled up by 10 to deal with half points

        if(selection == 0){
            if( int256(home_score*10)+rule > int256(away_score*10) ){
                win = 1;
            }
            else if( int256(home_score*10)+rule == int256(away_score*10) ){
                win = 2;
            }
        }
        else if(selection == 1){
            if( (int256(away_score*10)+rule) > int256(home_score*10)){
                win = 1;
            }
            else if( (int256(away_score*10)+rule) == int256(home_score*10) ){
                win = 2;
            }
        }
        else if (selection == 2 ){
            if(int256(home_score*10 + away_score*10) > rule){
                win = 1;
            }
            else if (int256(home_score*10 + away_score*10) == rule){
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



    function int2str(int i) internal pure returns (string memory){
        if (i == 0) return "0";
        bool negative = i < 0;
        uint j = uint(negative ? -i : i);
        uint l = j;     // Keep an unsigned copy
        uint len;
        while (j != 0){
            len++;
            j /= 10;
        }
        if (negative) ++len;  // Make room for '-' sign
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (l != 0){
            bstr[k--] = byte(uint8(48 + l % 10));
            l /= 10;
        }
        if (negative) {    // Prepend '-'
            bstr[0] = '-';
        }
        return string(bstr);
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


     function stringToUint(string memory s) internal view returns (uint result) {
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
    
    
   function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
    
        assembly { // solhint-disable-line no-inline-assembly
          result := mload(add(source, 32))
        }
    }

    function bytesToUInt(bytes32 v) internal pure returns (uint256 ret) {
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


 


