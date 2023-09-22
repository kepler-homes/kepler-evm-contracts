// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../common/TokenTransferer.sol";
import "./IPassportAllowlist.sol";


contract PassportAllowlist is OwnableUpgradeable, TokenTransferer, IPassportAllowlist {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => TokenStakeConfig) _tokenStakeConfigs;
    mapping(address => UserStake) _userStakes;

    mapping(address => uint256) _totalStakeUsers;
    mapping(address => uint256) _totalStakeAmounts;

    function queryTotalStakes(address token) external view override returns (uint256 userCount, uint256 stakeAmount) {
        userCount = _totalStakeUsers[token];
        stakeAmount = _totalStakeAmounts[token];
    }

    EnumerableSet.AddressSet private _supportedTokens;
    EnumerableSet.AddressSet private _admins;

    modifier onlyAdminOrOwner() {
        require(owner() == _msgSender() || _admins.contains(_msgSender()), "ONLY_ADMIN_OR_OWNER");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function addSupportedTokens(TokenStakeConfig[] memory items) public onlyAdminOrOwner {
        for (uint256 i = 0; i < items.length; i++) {
            TokenStakeConfig memory item = items[i];
            _tokenStakeConfigs[item.token] = item;
            _supportedTokens.add(item.token);
        }
    }

    function removeSupportedTokens(address[] memory items) public onlyAdminOrOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _supportedTokens.remove(items[i]);
        }
    }

    function querySupportedTokens() external view override returns (TokenStakeConfig[] memory tokens) {
        tokens = new TokenStakeConfig[](_supportedTokens.length());
        for (uint256 i; i < tokens.length; i++) {
            tokens[i] = _tokenStakeConfigs[_supportedTokens.at(i)];
        }
    }

    function addAdmins(address[] memory items) public onlyAdminOrOwner {
        for (uint256 i = 0; i < items.length; i++) {
            require(items[i] != address(0), "INVALID_TOKEN");
            _admins.add(items[i]);
        }
    }

    function removeAdmins(address[] memory items) public onlyAdminOrOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _admins.remove(items[i]);
        }
    }

    function getAdmins() external view returns (address[] memory admins) {
        admins = new address[](_admins.length());
        for (uint256 i; i < admins.length; i++) {
            admins[i] = _admins.at(i);
        }
    }

    function queryUserStake(address user) external view override returns (UserStake memory) {
        return _userStakes[user];
    }

    function stake(address token) external payable override {
        TokenStakeConfig memory config = _tokenStakeConfigs[token];
        require(config.token == token, "UNSUPPORTED_TOKEN");
        require(_userStakes[token].stakeTime == 0, "DUPLICATE_STAKE");
        address user = msg.sender;
        transferTokenFrom(token, user, config.amount);
        _userStakes[user] = UserStake({
            token: token,
            amount: config.amount,
            stakeTime: block.timestamp,
            duration: config.duration,
            unStaketime: 0
        });
        _totalStakeUsers[token] += 1;
        _totalStakeAmounts[token] += config.amount;
        emit StakeEvent(user, token, config.amount, block.timestamp, config.duration);
    }

    function unstake(address token) external override {
        address user = msg.sender;
        UserStake memory staking = _userStakes[user];
        require(staking.token == token && staking.amount > 0 && staking.unStaketime == 0, "STAKE_NOT_FOUND");
        require(staking.stakeTime + staking.duration <= block.timestamp, "INVALID_UNSTAKE_TIME");
        transferTokenTo(token, user, staking.amount);
        _userStakes[user].unStaketime = block.timestamp;
        _totalStakeUsers[token] -= 1;
        _totalStakeAmounts[token] += staking.amount;
        emit UnStakeEvent(user, token, staking.amount, block.timestamp);
    }

    function emergencyWithdraw(address token, address to, uint256 amount) public onlyOwner {
        transferTokenTo(token, to, amount);
    }
}
