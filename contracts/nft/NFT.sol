
pragma solidity ^0.8.4;

import "./KeplerNFT.sol";

contract NFT is KeplerNFT {
    function initialize(
        string memory name,
        string memory symbol,
        string memory baseURI_
    ) public initializer {
        __KeplerNFT_init(name, symbol, baseURI_);
    }
}
