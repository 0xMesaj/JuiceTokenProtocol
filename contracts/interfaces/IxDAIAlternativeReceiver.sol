// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IxDAIAlternativeReceiver{
    function relayTokens(address _from, address _receiver, uint256 _amount) external;
    function relayTokens(address _receiver, uint256 _amount) external;
    function relayTokens(address _receiver) external payable;
}
