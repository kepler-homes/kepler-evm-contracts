
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/SafeDecimalMath.sol";
import "./CorePool.sol";

contract RewardPool is CorePool, IRewardPool {
    using SafeDecimalMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint8 public constant WITHDRAW_COUNT = 12;

    uint256 public withdrawInterval;
    uint256 public rewardMultiplier;

    uint256 public nextRewardId;
    uint256 public lockedRewardAmount;
    uint256 public extraLockedRewardWeightedAmount;

    EnumerableSet.AddressSet private _depositPools;

    mapping(address => mapping(uint256 => LockedReward))
        internal _userLockedRewards;
    mapping(address => EnumerableSet.UintSet) internal _userLockedRewardIds;

    function initialize(
        address depositToken_,
        address rewardToken_,
        address poolFactory_,
        uint256 lockUnitDuration_,
        uint256 lockUnitMultiplier_,
        uint256 maxLockUnits_,
        uint256 withdrawInterval_,
        uint256 rewardMultiplier_
    ) public initializer {
        __CorePool_init(
            depositToken_,
            rewardToken_,
            address(this),
            poolFactory_,
            lockUnitDuration_,
            lockUnitMultiplier_,
            maxLockUnits_
        );
        nextRewardId = 20220219;
        withdrawInterval = withdrawInterval_;
        rewardMultiplier = rewardMultiplier_;
    }

    function withdraw(uint256 lockedRewardId) external override nonReentrant {
        _withdraw(msg.sender, lockedRewardId, msg.sender);
    }

    function withdrawTo(uint256 lockedRewardId, address to)
        external
        nonReentrant
    {
        _withdraw(msg.sender, lockedRewardId, to);
    }

    function _withdraw(
        address staker,
        uint256 lockedRewardId,
        address to
    ) private {
        LockedReward memory lockedReward = _userLockedRewards[staker][
            lockedRewardId
        ];
        require(lockedReward.amount > 0, "INVALID_REWARD");
        uint256 passedTime = block.timestamp - lockedReward.lastWithdrawTime;
        uint256 maxWithdrawCount = passedTime / withdrawInterval;
        require(
            maxWithdrawCount > lockedReward.withdrawCount,
            "INVALID_WITHDRAW_TIME"
        );

        uint256 _deductAmount = lockedReward.amount / WITHDRAW_COUNT;
        uint256 _weightedAmount = _deductAmount.multiplyDecimal(
            rewardMultiplier
        );
        uint256 withdrawAmount = _deductAmount +
            getWithdrawReward(lockedReward);

        if (lockedReward.withdrawCount == WITHDRAW_COUNT - 1) {
            delete _userLockedRewards[staker][lockedRewardId];
            _userLockedRewardIds[staker].remove(lockedRewardId);
        } else {
            lockedReward.withdrawCount += 1;
            lockedReward.lastWithdrawTime = block.timestamp;
            lockedReward.index = rewardIndex;
            lockedReward.remaingAmount -= _deductAmount;
            _userLockedRewards[staker][lockedRewardId] = lockedReward;
        }

        depoistAmount -= _deductAmount;
        lockedRewardAmount -= _deductAmount;
        extraWeightedAmount -= _weightedAmount;
        extraLockedRewardWeightedAmount -= _weightedAmount;
        IToken(rewardToken).transfer(to, withdrawAmount);
    }

    function lockReward(
        address staker,
        uint256 amount,
        address depositPool,
        address depositToken,
        uint256 depositId
    ) external override {
        require(_depositPools.contains(msg.sender), "ACCESS_DENIED");

        if (msg.sender != address(this)) {
            IToken(rewardToken).transferFrom(msg.sender, address(this), amount);
        }

        uint256 lockedRewardId = nextRewardId++;
        _userLockedRewardIds[staker].add(lockedRewardId);

        uint256 weightedAmount = amount.multiplyDecimal(rewardMultiplier);
        _userLockedRewards[staker][lockedRewardId] = LockedReward({
            id: lockedRewardId,
            amount: amount,
            remaingAmount: amount,
            index: rewardIndex,
            lockTime: block.timestamp,
            lastWithdrawTime: block.timestamp,
            withdrawCount: 0,
            depositPool: depositPool,
            depositToken: depositToken,
            depositId: depositId
        });

        depoistAmount += amount;
        extraWeightedAmount += weightedAmount;

        lockedRewardAmount += amount;
        extraLockedRewardWeightedAmount += weightedAmount;
    }

    function addDepositPools(address[] memory items) public onlyOwner {
        for (uint256 i; i < items.length; i++) {
            _depositPools.add(items[i]);
        }
    }

    function removeDepositPools(address[] memory items) public onlyOwner {
        for (uint256 i; i < items.length; i++) {
            _depositPools.remove(items[i]);
        }
    }

    function getDepositPools()
        external
        view
        returns (address[] memory depositPools)
    {
        depositPools = new address[](_depositPools.length());
        for (uint256 i; i < depositPools.length; i++) {
            depositPools[i] = _depositPools.at(i);
        }
    }

    function getLockedRewards(address staker)
        external
        view
        override
        returns (LockedReward[] memory)
    {
        LockedReward[] memory items = new LockedReward[](
            _userLockedRewardIds[staker].length()
        );
        for (uint256 i = 0; i < items.length; i++) {
            uint256 lockedRewardId = _userLockedRewardIds[staker].at(i);
            items[i] = _userLockedRewards[staker][lockedRewardId];
        }
        return items;
    }

    function getWithdrawReward(LockedReward memory lockedReward)
        public
        view
        returns (uint256)
    {
        uint256 index = rewardIndex - lockedReward.index;
        uint256 extraAmount = lockedReward.remaingAmount.multiplyDecimal(
            rewardMultiplier
        );
        uint256 amount = lockedReward.remaingAmount + extraAmount;
        return amount.multiplyDecimal(index);
    }
}