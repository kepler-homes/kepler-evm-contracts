
pragma solidity ^0.8.4;

import "../libraries/SafeDecimalMath.sol";

abstract contract BasePool {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    struct StakingItem {
        uint256 index;
        uint256 amount;
        uint256 pendingReward;
    }

    struct UserStakingItem {
        uint256 index;
        uint256 amount;
        uint256 pendingReward;
    }

    StakingItem public item;
    mapping(address => UserStakingItem) public userStakingItems;

    function _depositReward(uint256 amount) internal virtual {
        if (item.amount == 0) {
            item.pendingReward += amount;
        } else {
            amount += item.pendingReward;
            item.pendingReward = 0;
            item.index += amount.divideDecimal(item.amount);
        }
    }

    function _stake(address staker, uint256 amount) internal virtual {
        UserStakingItem memory userItem = userStakingItems[staker];
        uint256 index = item.index - userItem.index;
        userItem.pendingReward += userItem.amount.multiplyDecimal(index);
        userItem.index = item.index;
        userItem.amount += amount;
        userStakingItems[staker] = userItem;

        item.amount += amount;
    }

    function _unstake(address staker, uint256 amount) internal virtual {
        UserStakingItem memory userItem = userStakingItems[staker];
        require(userItem.amount >= amount, "INVALID_AMOUNT");
        uint256 index = item.index - userItem.index;
        userItem.pendingReward += userItem.amount.multiplyDecimal(index);
        userItem.index = item.index;
        userItem.amount -= amount;
        userStakingItems[staker] = userItem;
        item.amount -= amount;
    }

    function _pendingReward(address staker)
        internal
        view
        virtual
        returns (uint256 rewardAmount)
    {
        UserStakingItem memory userItem = userStakingItems[staker];
        uint256 index = item.index - userItem.index;
        rewardAmount =
            userItem.pendingReward +
            userItem.amount.multiplyDecimal(index);
    }

    function _claim(address staker)
        internal
        virtual
        returns (uint256 rewardAmount)
    {
        rewardAmount = _pendingReward(staker);
        userStakingItems[staker].index = item.index;
    }
}
