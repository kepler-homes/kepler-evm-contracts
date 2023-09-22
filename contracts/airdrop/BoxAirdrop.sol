// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "../libraries/Signature.sol";
import "../nft/IERC1155Mintable.sol";
import "./IBoxAirdrop.sol";
import "contracts/common/ERC1155Transferer.sol";

contract BoxAirdrop is OwnableUpgradeable, IBoxAirdrop, ERC1155Transferer, ERC1155HolderUpgradeable {
    address public constant SIGNER = 0xa4F8840A25E795c62B3584b53D84759e82dfFFFF;
    address public _boxNft;
    address public _keyNft;
    mapping(address => mapping(uint256 => uint256)) _claimRecords;

    function initialize(address boxNft, address keyNft) public initializer {
        __Ownable_init();
        _boxNft = boxNft;
        _keyNft = keyNft;
    }

    function batchClaim(
        uint256[] memory tokenIds,
        uint256[] memory maxAmounts,
        uint256[] memory amounts,
        bytes memory signature
    ) public override {
        address user = msg.sender;
        require(
            Signature.getSigner(keccak256Hash(user, tokenIds, maxAmounts, amounts), signature) == SIGNER,
            "INVALID_SIGNATURE"
        );
        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            require(_claimRecords[user][tokenId] + amount <= maxAmounts[i], "EXCEED_MAX_CLAIM_AMOUNT");
            IERC1155Mintable(_boxNft).mint(user, tokenId, amount, "");
            _claimRecords[user][tokenId] += amount;
            transferERC1155From(_keyNft, user, tokenId, amount);
        }
        emit ClaimEvent(user, tokenIds, amounts, block.timestamp);
    }

    function keccak256Hash(
        address user,
        uint256[] memory tokenIds,
        uint256[] memory maxAmounts,
        uint256[] memory amounts
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), user, tokenIds, maxAmounts, amounts));
    }

    function queryKeyNft() public view returns (address) {
        return _keyNft;
    }

    function updateKeyNft(address value) public onlyOwner {
        _keyNft = value;
    }

    function queryBoxNft() public view returns (address) {
        return _boxNft;
    }

    function updateBoxNft(address value) public onlyOwner {
        _boxNft = value;
    }

    function queryCliamRecords(address user) public view override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](5);
        for (uint i = 0; i < 5; i++) {
            amounts[i] = _claimRecords[user][i + 1];
        }
        return amounts;
    }

    function emergencyTransfer1155(
        address nft,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public onlyOwner {
        for (uint i; i < tokenIds.length; i++) {
            transferERC1155To(nft, to, tokenIds[i], amounts[i]);
        }
    }
}
