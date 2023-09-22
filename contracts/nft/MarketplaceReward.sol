// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../common/SafeAccess.sol";
import "../libraries/Signature.sol";
import "../nft/IERC1155Mintable.sol";
import "./IMarketplaceReward.sol";

contract MarketplaceReward is
    IMarketplaceReward,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    SafeAccess
{
    address public constant SIGNER = 0xa4F8840A25E795c62B3584b53D84759e82dfFFFF;
    address public keyNft;
    mapping(address => mapping(uint256 => uint256)) public claimRecords;
    mapping(address => uint256) public override cliamCountsOf;
    uint256[] public tokenIdProbabilities;
    uint256 private _nonce;

    function initialize(address keyNft_, uint256[] memory tokenIdProbabilities_) public initializer {
        __Ownable_init();
        keyNft = keyNft_;
        tokenIdProbabilities = tokenIdProbabilities_;
    }

    function queryTokenIdProbabilities() public view override returns (uint256[] memory) {
        return tokenIdProbabilities;
    }

    function updateTokenIdProbabilities(uint256[] memory val) public onlyOwner {
        tokenIdProbabilities = val;
    }

    function claimAll(
        uint256 totalRewardCount,
        bytes memory signature
    ) public override nonReentrant isNotContractCall whenNotPaused {
        address user = msg.sender;
        require(Signature.getSigner(keccak256Hash(user, totalRewardCount), signature) == SIGNER, "INVALID_SIGNATURE");
        require(cliamCountsOf[user] < totalRewardCount, "NOTHING_TO_CLAIM");
        uint256 count = totalRewardCount - cliamCountsOf[user];
        uint256[] memory tokenIds = new uint256[](count);
        for (uint i = count; i > 0; i--) {
            uint256 tokenId = _getRandomTokenId();
            IERC1155Mintable(keyNft).mint(user, tokenId, 1, "");
            claimRecords[user][tokenId]++;
            tokenIds[count - i] = tokenId;
        }
        cliamCountsOf[user] = totalRewardCount;
        emit ClaimEvent(user, tokenIds, block.timestamp);
    }

    function _getRandomTokenId() private returns (uint256) {
        require(tokenIdProbabilities.length == 5, "INVALID_TOKEN_ID_PROBABILITIES");
        uint256 randomNumber = (uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, _nonce++))) % 100);
        for (uint i; i < 5; i++) {
            if (randomNumber < tokenIdProbabilities[i]) return i + 1;
        }
        return 0;
    }

    function keccak256Hash(address user, uint256 totalRewardCount) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), user, totalRewardCount));
    }

    function updateKeyNft(address value) public onlyOwner {
        keyNft = value;
    }

    function queryCliamRecords(address user) public view override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](5);
        for (uint i = 0; i < 5; i++) {
            amounts[i] = claimRecords[user][i + 1];
        }
        return amounts;
    }
}
