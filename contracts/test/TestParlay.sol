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
        int[] rules;
    }

    mapping(bytes32 => Parlay ) public parlays;


    constructor(TestToken _dai,string[] memory ind,string[] memory sel, int[] memory rul) public{
        dai = _dai;
        dai.mint(address(this),12300000000);
        Parlay storage p = parlays[0x3139352c3335322c313832000000001230000000000000000000000000000000];
        p.odds = 0x3135352c31393300000000000000000000000000000000000000000000000000;
        p.amount = 50;
        p.indexes = ind;
        p.selections = sel;
        p.rules = rul;

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

    function buildParlay(string memory _indexes, string memory _selections, int[] memory _rules) public returns (bytes32 _queryID){
        string memory s;
        for(uint i = 0; i < _rules.length; i++){
            uint x = uint(_rules[i]);
            // s[i] = bytes32ToString(bytes32(x));
            if(i!=0){
                s = s.toSlice().concat(','.toSlice());
            }
            s = s.toSlice().concat(int2str(_rules[i]).toSlice()); // "abcdef"
        }

        console.log(s);

    }

       function resolveParlay( bytes32 _betID ) public {
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
            else if(ans == 2 ){
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
        
            console.log(odds);
            delete parlays[_betID];
            uint256 winAmt = amt.mul(odds).div(100);
            console.log(winAmt);
  
        }
    }


    function computeResult( uint256 _index, uint256 _selection, int256 _rule ) internal view returns(uint win){
        // MatchScores memory m = matchResults[_index];
        uint256 home_score = bytesToUInt(stringToBytes32("100"));
        uint256 away_score = bytesToUInt(stringToBytes32("80"));

        // console.log('_index: %s', _index);
        // console.log('_selection: %s', _selection);
        // console.logInt(_rule);

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


 


