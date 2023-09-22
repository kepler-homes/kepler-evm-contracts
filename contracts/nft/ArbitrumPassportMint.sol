// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IPassport.sol";
import "../common/SafeAccess.sol";
import "../common/TokenTransferer.sol";
import "../libraries/Signature.sol";

contract ArbitrumPassportMint is
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    SafeAccess,
    TokenTransferer
{
    uint8 private constant COMMISSION_RATE = 5;

    struct WLConfig {
        uint256 supply;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        uint256 saledAmount;
    }

    struct ReferenceRecording {
        address buyer;
        uint8 nftAmount;
        uint256 payment;
        uint256 reward;
        uint256 buyTime;
    }

    mapping(address => uint8) private _userBuyAmounts;
    mapping(uint8 => WLConfig) private _wlConfigs;
    mapping(address => ReferenceRecording[]) private _referenceRecordings;
    address private _passport;
    address private _signer;
    address private _vault;
    address private _currency;
    uint8 private _maxBuyAmount;

    function updateWLConfig(
        uint8 wlType,
        uint256 supply,
        uint256 price,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        _wlConfigs[wlType].supply = supply;
        _wlConfigs[wlType].price = price;
        _wlConfigs[wlType].startTime = startTime;
        _wlConfigs[wlType].endTime = endTime;
    }

    function queryBuyAmounts(address user) public view returns (uint8) {
        return _userBuyAmounts[user];
    }

    function queryWLConfig(uint8 wlType) public view returns (WLConfig memory) {
        return _wlConfigs[wlType];
    }

    function initialize(
        address passport,
        address signer,
        address vault,
        address currency,
        uint8 maxBuyAmount
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _updateConfig(passport, signer, vault, currency, maxBuyAmount);
    }

    function queryConfig()
        external
        view
        returns (address passport, address signer, address vault, address currency, uint8 maxBuyAmount)
    {
        passport = _passport;
        signer = _signer;
        vault = _vault;
        currency = _currency;
        maxBuyAmount = _maxBuyAmount;
    }

    function updateConfig(
        address passport,
        address signer,
        address vault,
        address currency,
        uint8 maxBuyAmount
    ) external onlyOwner {
        _updateConfig(passport, signer, vault, currency, maxBuyAmount);
    }

    function _updateConfig(
        address passport,
        address signer,
        address vault,
        address currency,
        uint8 maxBuyAmount
    ) private {
        _passport = passport;
        _signer = signer;
        _vault = vault;
        _currency = currency;
        _maxBuyAmount = maxBuyAmount;
    }

    function queryReferenceRecordings(address referrer) external view returns (ReferenceRecording[] memory) {
        return _referenceRecordings[referrer];
    }

    function buy(
        uint8 wlType,
        uint8 amount,
        address referrer,
        uint8 sog,
        bytes memory signature
    ) external payable isNotContractCall nonReentrant whenNotPaused {
        require(msg.sender != referrer, "INVALID_REFERRER");
        _verifySignature(msg.sender, wlType, sog, signature);
        require(amount > 0, "ZERO_AMOUNT");
        require(_vault != address(0), "EMPTY_VALUT");
        WLConfig memory config = _wlConfigs[wlType];
        require(config.price > 0, "INVALID_WL_TYPE");
        require(config.saledAmount + amount < config.supply, "EXCEED_MAX_SUPPLY");
        if (sog == 0) {
            require(_userBuyAmounts[msg.sender] + amount <= _maxBuyAmount, "EXCEED_MAX_BUY_AMOUNT");
            uint256 payment = amount * config.price;
            uint256 referenceReward = 0;
            if (referrer != address(0)) {
                referenceReward = (payment * COMMISSION_RATE) / 100;
            }
            transferTokenFrom(_currency, msg.sender, payment);
            transferTokenTo(_currency, _vault, payment - referenceReward);
            if (referenceReward > 0) {
                transferTokenTo(_currency, referrer, referenceReward);
                _referenceRecordings[referrer].push(
                    ReferenceRecording({
                        buyer: msg.sender,
                        nftAmount: amount,
                        payment: payment,
                        reward: referenceReward,
                        buyTime: block.timestamp
                    })
                );
            }
        }
        _userBuyAmounts[msg.sender] += amount;
        config.saledAmount += amount;
        _wlConfigs[wlType] = config;
        for (uint256 i; i < amount; i++) {
            IPassport(_passport).mint(msg.sender);
        }
    }

    function _verifySignature(address sender, uint8 wlType, uint8 sog, bytes memory signature) private view {
        bytes32 hash = keccak256Args(sender, wlType, sog);
        require(_signer == Signature.getSigner(hash, signature), "INVALID_SIGNATURE");
    }

    function keccak256Args(address sender, uint8 wlType, uint8 sog) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, wlType, sog));
    }
}
