pragma solidity >0.4.13 <0.7.7;
pragma experimental ABIEncoderV2;
import "./strings.sol";
import "./TestToken.sol";
import "./SafeMath.sol";
import 'hardhat/console.sol';


contract TestParlay{
    using strings for *;
    using SafeMath for uint256;
      
    bool public complete = false;
    int256 public ans = 0;
    uint256 public len = 0;
    strings.slice[] public test;
    TestToken dai;
    
    constructor(TestToken _dai) public{
        dai = _dai;
        dai.mint(address(this),12300000000);
    }
     
    function resolveParlay( bytes32 _odds ) public {

        bytes32 odds = _odds;
        strings.slice memory o = bytes32ToString(odds).toSlice();
             console.log('odds: %s', bytes32ToString(odds));
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1);
        len = os.length;
        bool win = true;
        for(uint i = 0; i < os.length; i++){
            int ans = 1;
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
            console.log(os[i].toString());
        }     
       
        if(win){
            // int256 odds = calculateParlayOdds(strings.join(','.toSlice(),os));

            // ans = odds;
            // complete = true;
            
            uint256 odds = calculateParlayOdds(os);
       
            uint256 amt = 5;
            address creator = msg.sender;
            uint payout = amt.mul(odds).div(100);
            // delete parlays[_betID];
            console.log('odds123: %s', odds);
            console.log('transfering: %s', payout);
            dai.transfer(msg.sender, payout);
        }
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
