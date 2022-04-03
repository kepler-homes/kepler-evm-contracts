
pragma solidity ^0.8.4;

interface IOracle {
    function queryPrices(address[] memory assets)
        external
        view
        returns (uint256[] memory prices);

    function queryPrice(address asset) external view returns (uint256 price);
}
