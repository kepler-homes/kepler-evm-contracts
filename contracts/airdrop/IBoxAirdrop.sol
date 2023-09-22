// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


interface IBoxAirdrop {
    event ClaimEvent(address indexed user, uint256[] tokenIds, uint256[] amounts, uint256 timestamp);

    function batchClaim(
        uint256[] memory tokenIds,
        uint256[] memory maxAmounts,
        uint256[] memory amounts,
        bytes memory signature
    ) external;

    function queryCliamRecords(address user) external view returns (uint256[] memory amounts);
}
