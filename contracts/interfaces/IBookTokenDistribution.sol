pragma solidity ^0.7.0;

interface IBookTokenDistribution
{
    function distributionComplete() external view returns (bool);
    
    function distribute() external payable;
    function claim(address _to, uint256 _contribution) external;
}