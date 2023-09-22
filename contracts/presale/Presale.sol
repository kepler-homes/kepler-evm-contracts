// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../swap/libraries/TransferHelper.sol";
import "../libraries/SafeDecimalMath.sol";
import "../libraries/Signature.sol";
import "../common/SafeAccess.sol";
import "../tokens/IToken.sol";
import "./IPresale.sol";
import "../oracle/IOracle.sol";

contract Presale is ReentrancyGuardUpgradeable, PausableUpgradeable, OwnableUpgradeable, SafeAccess, IPresale {
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 public constant UNIT = 1e18;

    address public constant SIGNER = 0xa4F8840A25E795c62B3584b53D84759e82dfFFFF;

    Config public config;

    EnumerableSet.AddressSet private _stableCoins;
    uint256[] public roundPrices;

    uint256 public saledUsdAmount;

    mapping(address => BuyRecord[]) public buyRecords;

    mapping(address => uint256) public claimedCounts;

    address public oracle;
    uint256 public orderId;

    mapping(address => uint256) public userBuyAmounts;

    function initialize(uint256 basePrice) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _initPrices(basePrice);
        orderId = 1;
    }

    function updateConfig(Config memory c) public onlyOwner {
        config = c;
    }

    function updateOracle(address val) public onlyOwner {
        oracle = val;
    }

    function getDecimals(address currency) private view returns (uint256) {
        return currency == address(0) ? 18 : uint256(IToken(currency).decimals());
    }

    function toDecimals18(uint256 value, uint256 decimals) private pure returns (uint256) {
        if (decimals < 18) return value * (10 ** (18 - decimals));
        if (decimals > 18) return value / (10 ** (decimals - 18));
        return value;
    }

    function buy2(address currency, uint256 amount, address referrer) external payable override {
        _buy(currency, amount, referrer);
    }

    function buy(address currency, uint256 amount, address referrer, bytes memory signature) external payable override {
        _verifySignature(msg.sender, signature);
        _buy(currency, amount, referrer);
    }

    function _verifySignature(address user, bytes memory signature) private view {
        bytes32 argsHash = keccak256Args(user);
        require(SIGNER == Signature.getSigner(argsHash, signature), "INVALID_SIGNATURE");
    }

    function keccak256Args(address user) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), user));
    }

    function _buy(address currency, uint256 amount, address referrer) private {
        require(timestamp() < config.claimStartTime, "BUY_FORBIDDEN");
        uint256 lockPeriods = 12;
        address user = msg.sender;
        require(user != referrer, "INVALID_REFERRER");
        require(config.commissionRate < 100 && config.commissionRate > 0, "INVALID_COMMISSION_RATE");
        uint256 usdAmount = toDecimals18(amount, getDecimals(currency));
        if (!_stableCoins.contains(currency)) {
            usdAmount = (IOracle(oracle).queryPrice(currency) * usdAmount) / UNIT;
            require(usdAmount > 0, "UNSUPORTED_CURRENCY");
        }
        require(usdAmount >= config.minBuyAmount, "INSUFFICIENT_BUY_AMOUNT");
        require(usdAmount <= config.maxBuyAmount, "EXCEED_BUY_AMOUNT");
        require(config.feeWallet != address(0), "ZERO_VAULT");

        uint256 reward;
        if (referrer != address(0)) {
            reward = (amount * config.commissionRate) / 100;
        }
        uint256 vTokenAmount = getBuyablevTokenAmount(usdAmount);
        saledUsdAmount += usdAmount;
        buyRecords[user].push(
            BuyRecord({
                buyer: user,
                referrer: referrer,
                vTokenAmount: vTokenAmount,
                currency: currency,
                currencyAmount: amount,
                usdAmount: usdAmount,
                reward: reward,
                time: timestamp(),
                lockPeriods: lockPeriods
            })
        );
        userBuyAmounts[user] += usdAmount;
        emit BuyEvent(
            orderId++,
            user,
            referrer,
            config.vToken,
            vTokenAmount,
            currency,
            amount,
            usdAmount,
            reward,
            lockPeriods,
            timestamp()
        );
        if (currency == address(0)) {
            require(msg.value == amount, "INVALID_MSG_VALUE");
            (bool s, ) = config.feeWallet.call{ value: amount - reward }(new bytes(0));
            require(s, "TRANSFER_TO_FEE_WALLET_FAILED");
            if (reward > 0) {
                (bool success, ) = referrer.call{ value: reward }(new bytes(0));
                require(success, "TRANSFER_TO_REFERRER_FAILED");
            }
        } else {
            require(IToken(currency).balanceOf(user) >= amount, "INSUFFICIENT_TOKEN_BALANCE");
            require(IToken(currency).allowance(user, address(this)) >= amount, "INSUFFICIENT_TOKEN_ALLOWANCE");
            IToken(currency).transferFrom(user, address(this), amount);
            if (reward > 0) {
                IToken(currency).transfer(referrer, reward);
            }
            IToken(currency).transfer(config.feeWallet, amount - reward);
        }
        require(IToken(config.vToken).balanceOf(address(this)) >= vTokenAmount, "INSUFFICIENT_VTOKEN_BALANCE");
        IToken(config.vToken).transfer(user, vTokenAmount);
    }

    function queryClaimables(address user) public view override returns (Claimable[] memory) {
        if (timestamp() <= config.claimStartTime) {
            return new Claimable[](0);
        }

        uint256 maxClaimCout = SafeDecimalMath.min(
            (timestamp() - config.claimStartTime) / config.claimInterval,
            queryMaxCliamCount(user)
        );

        uint256 claimedCount = claimedCounts[user];
        if (maxClaimCout <= claimedCount) {
            return new Claimable[](0);
        }

        Claimable[] memory claimables = new Claimable[](maxClaimCout - claimedCount);
        for (uint256 i; i < claimables.length; i++) {
            uint256 index = i + claimedCount;
            uint256 amount = queryClaimAmount(user, index);
            claimables[i] = Claimable(index, amount);
        }
        return claimables;
    }

    function claim() external override {
        address user = msg.sender;
        Claimable[] memory claimables = queryClaimables(user);
        require(claimables.length > 0, "NOTHING_TO_CLAIM");
        uint256 totalAmount = 0;
        uint256 claimedCount = claimedCounts[user];
        for (uint256 i; i < claimables.length; i++) {
            totalAmount += claimables[i].amount;
            emit ClaimEvent(user, claimedCount + i, claimables[i].amount, timestamp());
        }
        claimedCounts[user] += claimables.length;

        require(IToken(config.vToken).balanceOf(user) >= totalAmount, "INSUFFICIENT_TOKEN_BALANCE");
        require(IToken(config.vToken).allowance(user, address(this)) >= totalAmount, "INSUFFICIENT_TOKEN_ALLOWANCE");
        IToken(config.vToken).transferFrom(user, address(this), totalAmount);
        IToken(config.vToken).burn(totalAmount);

        require(IToken(config.token).balanceOf(address(this)) >= totalAmount, "INSUFFICIENT_KEPL_BALANCE");
        IToken(config.token).transfer(user, totalAmount);
    }

    function addStableCoins(address[] memory items) public onlyOwner {
        for (uint256 i; i < items.length; i++) {
            _stableCoins.add(items[i]);
        }
    }

    function removeStableCoins(address[] memory items) public onlyOwner {
        for (uint256 i; i < items.length; i++) {
            _stableCoins.remove(items[i]);
        }
    }

    function queryStableCoins() external view override returns (address[] memory stableCoins) {
        stableCoins = new address[](_stableCoins.length());
        for (uint256 i; i < stableCoins.length; i++) {
            stableCoins[i] = _stableCoins.at(i);
        }
    }

    function queryMaxCliamCount(address user) private view returns (uint256 claimCount) {
        for (uint256 i; i < buyRecords[user].length; i++) {
            uint256 lockPeriods = buyRecords[user][i].lockPeriods;
            if (claimCount < lockPeriods) {
                claimCount = lockPeriods;
            }
        }
    }

    function queryClaimAmount(address user, uint256 claimIndex) public view override returns (uint256 claimAmount) {
        for (uint256 i; i < buyRecords[user].length; i++) {
            BuyRecord memory record = buyRecords[user][i];
            if (record.lockPeriods > claimIndex) {
                claimAmount += record.vTokenAmount / record.lockPeriods;
            }
        }
    }

    function getBuyablevTokenAmount(uint256 amount) private view returns (uint256) {
        uint256 saledAmount = saledUsdAmount;
        uint256 saleAmountPerRound = config.saleAmountPerRound;
        uint256 round = saledAmount / saleAmountPerRound;

        uint256 vTokenAmount = 0;
        for (uint256 i = round; i < roundPrices.length; i++) {
            uint256 roundMaxAmount = (i + 1) * saleAmountPerRound;
            if (saledAmount + amount > roundMaxAmount) {
                uint256 amount_ = roundMaxAmount - saledAmount;
                vTokenAmount += (amount_ * UNIT) / roundPrices[i];
                amount -= amount_;
                saledAmount += amount_;
            } else {
                vTokenAmount += (amount * UNIT) / roundPrices[i];
                break;
            }
        }
        return vTokenAmount;
    }

    function updateBasicPrice(uint256 val) external onlyOwner {
        uint256 roundCount = 10;
        require(roundPrices.length == roundCount, "INVALID_ROUND_PRICES");
        uint256 price = val;
        for (uint256 i; i < roundCount; i++) {
            roundPrices[i] = price;
            price = (price * 105) / 100;
            if (i > 2) {
                break;
            }
        }
    }

    function _initPrices(uint256 basePrice) private {
        uint256 roundCount = 10;
        uint256 inflationRate = 2;
        uint256[] memory prices = new uint256[](roundCount);
        uint256 price = basePrice;
        for (uint256 i; i < roundCount; i++) {
            prices[i] = price;
            price = (price * (100 + inflationRate)) / 100;
        }
        roundPrices = prices;
    }

    function queryBuyRecords(address user) external view override returns (BuyRecord[] memory) {
        return buyRecords[user];
    }

    function queryConfig() external view override returns (Config memory) {
        return config;
    }

    function queryRoundPrices() external view override returns (uint256[] memory) {
        return roundPrices;
    }

    function querySaledUsdAmount() public view override returns (uint256) {
        return saledUsdAmount;
    }

    function emergencyWithdraw(address token, address to, uint256 amount) public onlyOwner {
        if (token == address(0)) {
            TransferHelper.safeTransferETH(to, amount);
        } else {
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    function timestamp() private view returns (uint256) {
        return block.timestamp;
    }
}
