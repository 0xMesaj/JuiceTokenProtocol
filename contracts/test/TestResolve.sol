pragma solidity >0.4.13 <0.7.7;


import "../SafeMath.sol";
import "../strings.sol";
pragma experimental ABIEncoderV2;
import 'hardhat/console.sol';

/*
Purpose of this contract is to test the wager resolution logic of the sports book.
Basically take out the Chainlink portion of the sportsbook so I can test easier
*/

contract TestResolve{
    int public win;
    using SafeMath for uint256;
    using SafeMath for int256;

    function computeResult( string memory score1, string memory score2, uint256 _selection, int256 _rule ) external {
        uint home_score = bytesToUInt(stringToBytes32(score1));
        uint away_score = bytesToUInt(stringToBytes32(score2));

        uint selection = _selection;
        int rule = _rule;

        if(selection == 0){
            if( int(home_score*10)+rule > int(away_score*10) ){
                win = 1;
                console.log("win");
            }
            else if( int(home_score*10) + rule == int(away_score*10) ){
                win = 2;
                console.log("draw");
            }
            else{
                win = 0;
                console.log("loss");
            }
        }
        else if(selection == 1){
            if( (int(away_score*10)+rule) > int(home_score*10)){
                console.log("win");
                win = 1;
            }
            else if( (int(away_score*10)+rule) == int(home_score*10) ){
                win = 2;
                console.log("draw");
            }
            else{
                win = 0;
                console.log("loss");
            }
        }
        else if (selection == 2 ){
            if(int(home_score*10 + away_score*10) > rule){
                win = 1;
                // console.log("win");
            }
            else if (int(home_score*10 + away_score*10) == rule){
                win = 2;
                // console.log("draw");
            }
            else{
                win = 0;
                // console.log("loss");
            }
        }
        else if(selection == 3){
            if(rule > int(home_score*10 + away_score*10)){
                win = 1;
                // console.log("win");
            }
            else if (rule == int(home_score*10 + away_score*10)){
                win = 2;
                // console.log("draw");
            }
            else{
                win = 0;
                // console.log("loss");
            }
        }
        else if(selection == 4 ){
            if((home_score > away_score)){
                win = 1;
                // console.log("win");
            }
            else if (home_score == away_score){
                win = 2;
                // console.log("draw");
            }
            else{
                win = 0;
                // console.log("loss");
            }
        }
        else if (selection == 5 ){
            if(away_score > home_score){
                win = 1;
                // console.log("win");
            }
            else if(away_score == home_score){
                win = 2;
                // console.log("draw");
            }
            else{
                win = 0;
                // console.log("loss");
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

    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
    
        assembly { // solhint-disable-line no-inline-assembly
          result := mload(add(source, 32))
        }
     }
}