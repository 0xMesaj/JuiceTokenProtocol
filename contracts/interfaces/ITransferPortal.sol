pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

struct TransferPortalTarget
{
    address destination;
    uint256 amount;
}

interface ITransferPortal
{
    function handleTransfer(address msgSender, address from, address to, uint256 amount) external
        returns (TransferPortalTarget[] memory targets);
}