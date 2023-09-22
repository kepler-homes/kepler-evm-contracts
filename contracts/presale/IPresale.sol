// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IPresale {
    event BuyEvent(
        uint256 orderId,
        address indexed user,
        address indexed referrer,
        address token,
        uint256 tokenAmount,
        address currency,
        uint256 currencyAmount,
        uint256 usdAmount,
        uint256 reward,
        uint256 lockPeriods,
        uint256 timestamp
    );

    event ClaimEvent(
        address indexed user,
        uint256 index,
        uint256 amount,
        uint256 timestamp
    );

    struct BuyRecord {
        address buyer;
        address referrer;
        uint256 vTokenAmount;
        address currency;
        uint256 currencyAmount;
        uint256 usdAmount;
        uint256 reward;
        uint256 time;
        uint256 lockPeriods;
    }

    struct Claimable {
        uint256 index;
        uint256 amount;
    }

    struct Config {
        uint256 claimStartTime;
        uint256 commissionRate;
        address vToken;
        address token;
        address feeWallet;
        uint256 saleAmountPerRound;
        uint256 claimInterval;
        uint256 minBuyAmount;
        uint256 maxBuyAmount;
        uint256 refeererMinBuyAmount;
    }

    function buy2(address usdToken, uint256 usdAmount, address referrer) external payable;

    function buy(address usdToken, uint256 usdAmount, address referrer, bytes memory signature) external payable;

    function queryStableCoins() external view returns (address[] memory stableCoins);

    function claim() external;

    function queryClaimAmount(address user, uint256 claimIndex) external view returns (uint256 claimAmount);

    function queryClaimables(address user) external view returns (Claimable[] memory);

    function queryBuyRecords(address user) external view returns (BuyRecord[] memory);

    function queryConfig() external view returns (Config memory);

    function queryRoundPrices() external view returns (uint256[] memory);

    function querySaledUsdAmount() external view returns (uint256);
}
