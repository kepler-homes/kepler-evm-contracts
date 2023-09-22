// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../libraries/Signature.sol";
import "../nft/IERC1155Mintable.sol";
import "./IAvatarAirdrop.sol";


contract AvatarAirdrop is OwnableUpgradeable, IAvatarAirdrop {
    using EnumerableSet for EnumerableSet.UintSet;
    event DrawEvent(address indexed user, uint256 tokenId);

    address public constant SIGNER = 0xa4F8840A25E795c62B3584b53D84759e82dfFFFF;
    uint256 public constant GENDER_FEMALE = 0;
    uint256 public constant GENDER_MALE = 1;

    address public nft;

    uint256 public constant TOKEN_ID_COUNT = 10;

    mapping(address => uint256) private _userTokenIds;
    mapping(uint256 => uint256) private _genderBalances;

    mapping(uint256 => uint256) private _tokenIdBalances;

    uint256 private _totalBalance;

    EnumerableSet.UintSet _batchIds;
    mapping(uint256 => uint256) private _batchIdMintAmounts;

    function initialize(address nft_) public initializer {
        __Ownable_init();
        initBalances(GENDER_MALE);
        initBalances(GENDER_FEMALE);
        nft = nft_;
    }

    function initBalances(uint256 gender) private {
        uint genderTotalBalance = 10000;
        _genderBalances[gender] = genderTotalBalance;
        for (uint i = 0; i < TOKEN_ID_COUNT; i++) {
            uint256 tokenId = gender * 100 + 1 + i;
            _tokenIdBalances[tokenId] = genderTotalBalance / TOKEN_ID_COUNT;
        }
        _totalBalance += genderTotalBalance;
    }

    function queryUserTokenId(address user) public view override returns (uint256) {
        return _userTokenIds[user];
    }

    function queryGenderBalances() public view override returns (uint256 maleBalance, uint256 femaleBalance) {
        maleBalance = _genderBalances[GENDER_MALE];
        femaleBalance = _genderBalances[GENDER_FEMALE];
    }

    function queryBatchIdMintAmounts()
        public
        view
        override
        returns (uint256[] memory batchIds, uint256[] memory amounts)
    {
        batchIds = new uint256[](_batchIds.length());
        amounts = new uint256[](batchIds.length);
        for (uint256 i; i < batchIds.length; i++) {
            uint256 batchId = _batchIds.at(i);
            batchIds[i] = batchId;
            amounts[i] = _batchIdMintAmounts[batchId];
        }
    }

    function queryTokenIdBalances(
        uint256 gender
    ) public view override returns (uint256[] memory tokenIds, uint256[] memory balances) {
        tokenIds = new uint256[](TOKEN_ID_COUNT);
        balances = new uint256[](TOKEN_ID_COUNT);
        for (uint i = 0; i < TOKEN_ID_COUNT; i++) {
            uint256 tokenId = gender * 100 + 1 + i;
            tokenIds[i] = tokenId;
            balances[i] = _tokenIdBalances[tokenId];
        }
    }

    function draw(
        uint256 batchId,
        uint256 batchSupply,
        uint256 gender,
        bytes memory signature
    ) public override {
        address user = msg.sender;
        require(
            Signature.getSigner(keccak256Hash(user, batchId, batchSupply), signature) == SIGNER,
            "INVALID_SIGNATURE"
        );
        require(_userTokenIds[user] == 0, "DUPLICATE_DRAW");
        require(gender == 0 || gender == 1, "INVALID_GENDER");
        require(_batchIdMintAmounts[batchId] < batchSupply, "EXCEED_BATCH_SUPPLY");
        uint256 tokenId = _draw(gender, _pseudoRandom());
        _userTokenIds[user] = tokenId;
        _genderBalances[gender]--;
        _tokenIdBalances[tokenId]--;
        _totalBalance--;
        _batchIdMintAmounts[batchId]++;
        _batchIds.add(batchId);
        IERC1155Mintable(nft).mint(user, tokenId, 1, "");
        emit DrawEvent(user, tokenId);
    }

    function keccak256Hash(address user, uint256 batchId, uint256 batchSupply) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), user, batchId, batchSupply));
    }

    function _pseudoRandom() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, _totalBalance)));
    }

    function _draw(uint256 gender, uint256 random) private view returns (uint) {
        uint totalBalance = _genderBalances[gender];
        require(totalBalance > 0, "OUT_OF_SUPPLY");
        random = random % totalBalance;
        uint256 index = 0;
        for (uint i = 1; i <= TOKEN_ID_COUNT; i++) {
            uint256 tokenId = gender * 100 + i;
            uint256 balance = _tokenIdBalances[tokenId];
            if (balance == 0) continue;
            uint nextIndex = index + balance;
            if (index <= random && random < nextIndex) {
                return tokenId;
            }
            index = nextIndex;
        }
        revert("DARW_FAILED");
    }
}
