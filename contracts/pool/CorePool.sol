
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../libraries/SafeDecimalMath.sol";
import "../tokens/interfaces/IToken.sol";
import "./interfaces/IRewardPool.sol";
import "./interfaces/ICorePool.sol";
import "./interfaces/IPoolFactory.sol";

abstract contract CorePool is
    ICorePool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => uint256) public userTotalDeposits;
    mapping(address => mapping(uint256 => Deposit)) internal _userDeposits;
    mapping(address => EnumerableSet.UintSet) internal _userDepoistIds;

    uint256 public nextDepositId;

    uint256 public depoistAmount;
    uint256 public extraWeightedAmount;
    uint256 public rewardIndex;
    uint256 public totalRewards;
    uint256 public claimedRewards;
    uint256 public lastYieldBlock;

    address public depositToken;
    address public rewardToken;
    address public rewardPool;
    address public poolFactory;

    uint256 public lockUnitDuration;
    uint256 public lockUnitMultiplier;
    uint256 public maxLockUnits;

    function __CorePool_init(
        address depositToken_,
        address rewardToken_,
        address rewardPool_,
        address poolFactory_,
        uint256 lockUnitDuration_,
        uint256 lockUnitMultiplier_,
        uint256 maxLockUnits_
    ) public initializer {
        __Ownable_init();
        depositToken = depositToken_;
        rewardToken = rewardToken_;
        rewardPool = rewardPool_;
        poolFactory = poolFactory_;
        lockUnitDuration = lockUnitDuration_;
        lockUnitMultiplier = lockUnitMultiplier_;
        maxLockUnits = maxLockUnits_;
        nextDepositId = 20220219;

        IToken(rewardToken).approve(rewardPool, type(uint256).max);
    }

    function stake(uint256 amount, uint256 lockUnits) external override {
        _stakeTo(amount, lockUnits, msg.sender);
    }

    function stakeTo(
        uint256 amount,
        uint256 lockUnits,
        address to
    ) external {
        _stakeTo(amount, lockUnits, to);
    }

    function _stakeTo(
        uint256 amount,
        uint256 lockUnits,
        address to
    ) public {
        IToken token = IToken(depositToken);
        uint256 balance = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), amount);
        amount = token.balanceOf(address(this)) - balance;
        _stake(to, amount, lockUnits);
    }

    function getDeposit(address staker, uint256 depositId)
        external
        view
        override
        returns (Deposit memory)
    {
        return _userDeposits[staker][depositId];
    }

    function _stake(
        address staker,
        uint256 amount,
        uint256 lockUnits
    ) internal {
        require(lockUnits < maxLockUnits, "INVALID_LOCK_UNITS");
        yield();

        uint256 depositId = nextDepositId++;
        _userDepoistIds[staker].add(depositId);

        uint256 _extraWeightedAmount = amount.multiplyDecimal(
            lockUnits * lockUnitMultiplier
        );
        _userDeposits[staker][depositId] = Deposit({
            id: depositId,
            amount: amount,
            index: rewardIndex,
            extraWeightedAmount: _extraWeightedAmount,
            depositTime: block.timestamp,
            lockUnits: lockUnits
        });
        userTotalDeposits[staker] += amount;
        depoistAmount += amount;
        extraWeightedAmount += _extraWeightedAmount;

        emit Stake(amount, lockUnits, depositId);
    }

    function updateLockUnitMultiplier(uint256 val) public onlyOwner {
        extraWeightedAmount = extraWeightedAmount
            .multiplyDecimal(val)
            .divideDecimal(lockUnitMultiplier);
        lockUnitMultiplier = val;
    }

    function yield() public {
        uint256 stakingAmount = depoistAmount + extraWeightedAmount;
        console.log("yield(),stakingAmount", stakingAmount);
        if (stakingAmount > 0) {
            if (lastYieldBlock > 0) {
                console.log("yield(),lastYieldBlock", lastYieldBlock);
                uint256 blocks = block.number - lastYieldBlock;
                if (blocks > 0) {
                    uint256 rewardsPerBlock = IPoolFactory(poolFactory)
                        .getRewardsPerBlock(address(this));

                    uint256 yieldAmount = blocks * rewardsPerBlock;
                    console.log("yield(),yieldAmount", yieldAmount);
                    if (yieldAmount > 0) {
                        IPoolFactory(poolFactory).mint(
                            rewardToken,
                            address(this),
                            yieldAmount
                        );

                        totalRewards += yieldAmount;
                        rewardIndex += yieldAmount.divideDecimal(stakingAmount);
                        console.log("yield(),totalRewards", totalRewards);
                        console.log("yield(),rewardIndex", rewardIndex);
                    }
                }
            }
            lastYieldBlock = block.number;
        }
    }

    function _pendingReward(address staker, uint256 depositId)
        internal
        view
        virtual
        returns (uint256)
    {
        Deposit memory deposit = _userDeposits[staker][depositId];
        uint256 index = rewardIndex - deposit.index;

        uint256 stakingAmount = deposit.amount + deposit.extraWeightedAmount;

        uint256 balance = IToken(rewardToken).balanceOf(address(this));
        uint256 rewardAmount = stakingAmount.multiplyDecimal(index);

        console.log("_pendingReward(),rewardIndex", rewardIndex);
        console.log("_pendingReward(),deposit.index", deposit.index);
        console.log("_pendingReward(),index", index);
        console.log("_pendingReward(),rewardAmount", rewardAmount);
        console.log(
            "_pendingReward(),rewardToken.balanceOf(this)",
            IToken(rewardToken).balanceOf(address(this))
        );
        return balance.min(rewardAmount);
    }

    function unstake(uint256 depositId) external override {
        _unstakeTo(msg.sender, depositId, msg.sender);
    }

    function unstakeTo(uint256 depositId, address to) external {
        _unstakeTo(msg.sender, depositId, to);
    }

    function _unstakeTo(
        address staker,
        uint256 depositId,
        address to
    ) internal {
        (uint256 depositAmount, uint256 rewardAmount) = _unstake(
            staker,
            depositId
        );
        IToken(depositToken).transfer(to, depositAmount);
        if (rewardAmount > 0) {
            IRewardPool(rewardPool).lockReward(
                to,
                rewardAmount,
                address(this),
                depositToken,
                depositId
            );
        }
    }

    function _unstake(address staker, uint256 depositId)
        internal
        returns (uint256 depositAmount, uint256 rewardAmount)
    {
        yield();
        Deposit memory deposit = _userDeposits[staker][depositId];
        require(
            deposit.lockUnits == 0 ||
                block.number - deposit.depositTime >
                deposit.lockUnits * lockUnitDuration,
            "INVALID_UNSTAKE_TIME"
        );
        depositAmount = deposit.amount;
        rewardAmount = _pendingReward(staker, depositId);
        delete _userDeposits[staker][depositId];
        _userDepoistIds[staker].remove(depositId);
        userTotalDeposits[staker] -= depositAmount;
        depoistAmount -= deposit.amount;
        extraWeightedAmount -= extraWeightedAmount;

        emit Unstake(depositAmount, depositId, rewardAmount);
    }

    function pendingReward(address staker, uint256 depositId)
        external
        view
        override
        returns (uint256 rewardAmount)
    {
        return _pendingReward(staker, depositId);
    }

    function claim(uint256 depositId) external override {
        _claimTo(msg.sender, depositId, msg.sender);
    }

    function claimTo(uint256 depositId, address to) external {
        _claimTo(msg.sender, depositId, to);
    }

    function _claimTo(
        address staker,
        uint256 depositId,
        address to
    ) internal {
        uint256 rewardAmount = _claim(staker, depositId);
        if (rewardAmount > 0) {
            IRewardPool(rewardPool).lockReward(
                to,
                rewardAmount,
                address(this),
                depositToken,
                depositId
            );
        }
    }

    function _claim(address staker, uint256 depositId)
        internal
        returns (uint256 rewardAmount)
    {
        yield();
        rewardAmount = _pendingReward(staker, depositId);
        _userDeposits[staker][depositId].index = rewardIndex;
        claimedRewards += rewardAmount;
        emit Claim(depositId, rewardAmount);
    }


    function getUserDepoistIds(address staker)
        public
        view
        returns (uint256[] memory depositIds)
    {
        depositIds = new uint256[](_userDepoistIds[staker].length());
        for (uint256 i; i < depositIds.length; i++) {
            depositIds[i] = _userDepoistIds[staker].at(i);
        }
    }

    function getUserDepoistCount(address staker) public view returns (uint256) {
        return _userDepoistIds[staker].length();
    }

    function getUserDepoists(address staker)
        public
        view
        returns (Deposit[] memory deposits)
    {
        deposits = new Deposit[](_userDepoistIds[staker].length());
        for (uint256 i; i < deposits.length; i++) {
            deposits[i] = _userDeposits[staker][_userDepoistIds[staker].at(i)];
        }
    }
}