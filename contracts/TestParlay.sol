pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "./strings.sol";
import 'hardhat/console.sol';

contract TestParlay{
    using strings for *;

    uint256 public ans = 0;
    constructor(){

    }
     
    function resolveParlay( bytes32 _odds ) public returns (uint256 odds){

        bytes32 byteOdds = _odds;
        strings.slice memory o = bytes32ToString(byteOdds).toSlice();
        
        strings.slice memory delim = ",".toSlice();
        strings.slice[] memory os = new strings.slice[](o.count(delim) + 1); 

        bool win = true;
        for(uint i = 0; i < os.length; i++){
            os[i] = o.split(delim);

            int ans = 1;
            if(ans == 0){
                win = false;
            }
            else if(ans == 2){
                os[i] = '100'.toSlice();
            }

        }     
      
        if(win){

            odds = calculateParlayOdds(os);
            ans = odds;
            console.log(ans/100);
        }
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
