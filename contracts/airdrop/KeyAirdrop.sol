// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../libraries/Signature.sol";
import "../nft/IERC1155Mintable.sol";
import "./IKeyAirdrop.sol";

contract KeyAirdrop is OwnableUpgradeable, IKeyAirdrop {
    address public constant SIGNER = 0xa4F8840A25E795c62B3584b53D84759e82dfFFFF;
    address public _keyNft;
    mapping(address => mapping(uint256 => uint256)) _claimRecords;

    function initialize(address keyNft) public initializer {
        __Ownable_init();
        _keyNft = keyNft;
    }

    function batchClaim(uint256[] memory tokenIds, uint256[] memory amounts, bytes memory signature) public override {
        address user = msg.sender;
        require(Signature.getSigner(keccak256Hash(user, tokenIds, amounts), signature) == SIGNER, "INVALID_SIGNATURE");
        for (uint i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            require(_claimRecords[user][tokenId] == 0, "DUPLICATE_CLAIM");
            IERC1155Mintable(_keyNft).mint(user, tokenId, amount, "");
            _claimRecords[user][tokenId] += amount;
        }
        emit ClaimEvent(user, tokenIds, amounts, block.timestamp);
    }

    function keccak256Hash(
        address user,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), user, tokenIds, amounts));
    }

    function queryKeyNft() public view returns (address) {
        return _keyNft;
    }

    function updateKeyNft(address value) public onlyOwner {
        _keyNft = value;
    }

    function queryCliamRecords(address user) public view override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](5);
        for (uint i = 0; i < 5; i++) {
            amounts[i] = _claimRecords[user][i + 1];
        }
        return amounts;
    }
}
