// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


interface IPassportAllowlist {
    struct TokenStakeConfig {
        address token;
        uint256 amount;
        uint256 duration;
    }

    struct UserStake {
        address token;
        uint256 amount;
        uint256 stakeTime;
        uint256 duration;
        uint256 unStaketime;
    }

    event StakeEvent(address user, address token, uint256 amount, uint256 timestamp, uint256 duration);
    event UnStakeEvent(address user, address token, uint256 amount, uint256 timestamp);

    function queryTotalStakes(
        address token
    )
        external
        view
        returns (
            uint256 userCount,
            uint256 stakeAmount
        );

    function querySupportedTokens() external view returns (TokenStakeConfig[] memory tokens);

    function queryUserStake(address user) external view returns (UserStake memory);

    function stake(address token) external payable;

    function unstake(address token) external;
}
