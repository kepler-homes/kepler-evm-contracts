// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IMarketplaceReward {
    event ClaimEvent(address user, uint256[] tokenIds, uint256 timestamp);

    function queryTokenIdProbabilities() external view returns (uint256[] memory);

    function claimAll(uint256 totalRewardCount, bytes memory signature) external;

    function queryCliamRecords(address user) external view returns (uint256[] memory);

    function cliamCountsOf(address user) external view returns (uint256);
}
