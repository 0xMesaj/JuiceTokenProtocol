pragma solidity >0.4.13 <0.7.7;
pragma experimental ABIEncoderV2;
import "../strings.sol";
import "./TestToken.sol";
import "../SafeMath.sol";
import 'hardhat/console.sol';


contract TestParlay{
    using strings for *;
    using SafeMath for uint256;
      
    bool public complete = false;
    int256 public ans = 0;
    uint256 public len = 0;
    strings.slice[] public test;
    TestToken dai;
    

      struct Parlay{
        uint256 amount;
        uint256 timestamp;
        bytes32 odds;
        
        address creator;
        
        string[] indexes;
        string[] selections;
        string[] rules;
    }

    mapping(bytes32 => Parlay ) public parlays;


    constructor(TestToken _dai,string[] memory ind,string[] memory sel, string[] memory rul) public{
        dai = _dai;
        dai.mint(address(this),12300000000);
        Parlay storage p = parlays[0x3139352c3335322c313832000000001230000000000000000000000000000000];
        p.odds = 0x3139352c3335322c313832000000000000000000000000000000000000000000;
        
        p.indexes = ind;
        p.selections = sel;
        p.rules = rul;

    }

   
    function resolveParlay( bytes32 _betID ) public {
        Parlay memory p = parlays[_betID];
        require(_betID != 0x0, "Invalid Bet Reference");

       
        strings.slice memory o = bytes32ToString(p.odds).toSlice();
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1);

        // bytes32 odds = p.odds;rules

        bool win = true;

        for(uint i = 0; i < os.length-1; i++){
            bytes32 test = stringToBytes32(p.indexes[i]);
            bytes32 test1 = stringToBytes32(p.selections[i]);
            bytes32 test2 = stringToBytes32(p.rules[i]);

            int ans = computeResult(uint(stringToBytes32(p.indexes[i])),uint(stringToBytes32(p.selections[i])), int(stringToBytes32(p.rules[i])));
            if(i==0){
                ans = 2;
            }
            if(ans == 0){
                win = false;
            }
            else if(ans == 2){
                os[i] = '100'.toSlice();
            }
            else{
                os[i] = o.split(delim);
            }
        }     
       
        if(win){
            uint256 odds = calculateParlayOdds(os);
            uint256 amt = 5;
            address creator = msg.sender;
            uint payout = amt.mul(odds).div(100);
            // delete parlays[_betID];
            console.log('odds: %s', odds);
            console.log('transfering: %s', payout);
            dai.transfer(msg.sender, payout);
        }
    }



    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) internal view returns(int win){
        // MatchScores memory m = matchResults[_index];
        console.log("yoo");
        uint256 home_score = bytesToUInt(stringToBytes32("123"));
        uint256 away_score = bytesToUInt(stringToBytes32("120"));
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
      
    
        /* Utilities */
    function calculateParlayOdds(strings.slice[] memory o) public returns (uint256 odds){
        odds = 1;
        for(uint i=0;i < o.length; i++){
            if(i==0){
                //  console.log('odds123: %s', stringToUint(o[i].toString()));
                odds *= stringToUint(o[i].toString());
            }
            else{
                odds = odds*stringToUint(o[i].toString())/100;
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


 


