// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*

    Bridge to XDAI

*/

import "./interfaces/IxDAIAlternativeReceiver.sol";
import "./interfaces/IERC206.sol";
import "./SafeMath6.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";

import 'hardhat/console.sol';
contract BridgeToXDAI is ChainlinkClient {
    using SafeMath for uint256;

    address oracle;
    address treasury;
    address dai;
    address mesaj;
    address xDAIcontract;
    uint256 public BALANCER_ORACLE_PAYMENT = 1 * LINK; // 1 Link
    uint256 lastBalance;
    bool initSplit;
    IxDAIAlternativeReceiver immutable tokenbridge;
    
    mapping(address => bool) public wards;

    modifier isWard(){
        require (wards[msg.sender], "Error: Wards only");
        _;
    }

    modifier isOracle(){
        require (msg.sender == oracle , "Error: Oracle only");
        _;
    }
    
    constructor(address _xDAIcontract,address _dai) public {
        // setPublicChainlinkToken();
        wards[msg.sender] = true;
        mesaj = msg.sender;
        dai = _dai;
        xDAIcontract = _xDAIcontract;
        tokenbridge = IxDAIAlternativeReceiver(0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016);
    }

    // Appoint address as ward
    function setWard(address _appointee) public isWard(){
        require(!wards[_appointee], "Appointee is already ward.");
        wards[_appointee] = true;
    }

    // Set Treasury, Only Callable Once
    function setTreasury(address _treasury) public isWard(){
        require(treasury == address(0x0), "Treasury Already Set.");
        treasury = _treasury;
    }

    // Abdicate ward address
    function abdicate(address _shame) public isWard(){
        require(mesaj != _shame, "Et tu, Brute?");
        wards[_shame] = false;
    }

    function setBalancerOraclePayment(uint256 amt) public isWard(){
        BALANCER_ORACLE_PAYMENT = amt;
    }

    function initialSplit() public isWard(){
        require(!initSplit, "Function already called");
        uint256 daiBalance = IERC20(dai).balanceOf(treasury).div(2);
        if(daiBalance > 10000000 * 10**18){ // Max transfer is 10 mil
            daiBalance = 9999999 * 10**18;
        }
        tokenbridge.relayTokens(treasury,xDAIcontract,daiBalance);   // send DAI to xDAI bridge to xDAI contract address
        initSplit = true;
    }

    function balancePools() public isWard() returns(bytes32 _queryID){
        require(block.timestamp >= lastBalance + 277);  // 1 HR assuming 13 sec block times
        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32('9ba77e3c02f2408ca2b9679f70a54d01'), address(this), this.fulfillBalanceCheck.selector);
        req.add('type', 'xdaiBalance');
        req.add('origin', 'ETH');
        _queryID = sendChainlinkRequestTo(oracle, req, BALANCER_ORACLE_PAYMENT);
        lastBalance = block.number;
    }

    function fulfillBalanceCheck(bytes32 _requestId, uint256 _balance) public isOracle() recordChainlinkFulfillment(_requestId){
        uint256 daiBalance = IERC20(dai).balanceOf(treasury);
        if(daiBalance > _balance){
            uint256 delta = daiBalance.sub(_balance);
            uint256 amtToSend = delta.div(2);
            if(amtToSend > 10000000 * 10**18){ // Max transfer is 10 mil
                amtToSend = 9999999 * 10**18;
            }
            tokenbridge.relayTokens(treasury,xDAIcontract,amtToSend);   // send DAI to xDAI bridge to xDAI contract address
        }
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
}