// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


interface IAvatarAirdrop {
    function draw(
        uint256 batchId,
        uint256 batchSupply,
        uint256 gender,
        bytes memory signature
    ) external;

    function queryUserTokenId(address user) external view returns (uint256);

    function queryGenderBalances() external view returns (uint256 maleBalance, uint256 femaleBalance);

    function queryBatchIdMintAmounts() external view returns (uint256[] memory batchIds, uint256[] memory amounts);

    function queryTokenIdBalances(
        uint256 gender
    ) external view returns (uint256[] memory tokenIds, uint256[] memory balances);
}
