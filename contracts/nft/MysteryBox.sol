
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "../libraries/Signature.sol";
import "../common/Minable.sol";
import "./interfaces/IMysteryBox.sol";
import "../libraries/SafeDecimalMath.sol";
import "./interfaces/IKeplerNFT.sol";

contract MysteryBox is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    Minable,
    IMysteryBox
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeDecimalMath for uint256;

    uint8 internal constant USER_MAX_MINT_COUNT = 9;

    uint8 internal constant SUIT_PART_COUNT = 6;
    uint8 internal constant FEMALE = 0;
    uint8 internal constant MALE = 1;

    uint256 public nextTokenId;
    PaymentConfig public paymentConfig;
    ReferenceConfig public referenceConfig;
    MintConfig public mintConfig;

    mapping(uint256 => EnumerableSet.UintSet) private _genderTokenIds;
    mapping(address => uint8) private _userMintCounts;

    mapping(address => EnumerableSet.UintSet) private _referralTokenIds;
    mapping(uint256 => ReferralClaimRecord[]) private _referralClaimRecords;

    EnumerableSet.AddressSet private _signers;
    mapping(uint256 => Item) private _tokenIdItems;

    function initialize(
        string memory name_,
        string memory symbol_,
        address signer_
    ) public initializer {
        __Ownable_init();
        __ERC721_init(name_, symbol_);
        addMinter(msg.sender);
        _signers.add(msg.sender);
        _signers.add(signer_);
        nextTokenId = 1000;
        paymentConfig.genisTime = _currentTimestamp();
    }

    function updateReferenceConfig(ReferenceConfig memory config)
        public
        onlyOwner
    {
        require(config.cliamInterval > 0, "INVALID_CLAIM_INTERVAL");
        require(config.cliamCount > 0, "INVALID_CLAIM_COUNT");
        require(config.rewardRate > 0, "INVALID_REWARD_RATE");
        referenceConfig = config;
        emit UpdateReferenceConfig(config);
    }

    function updateMintConfig(MintConfig memory config) public onlyOwner {
        require(config.maleMax > 0, "INVALID_MALE_MAX");
        require(config.femaleMax > 0, "INVALID_FEMALE_MAX");
        mintConfig = config;
        emit UpdateMintConfig(config);
    }

    function updatePaymentConfig(PaymentConfig memory config) public onlyOwner {
        require(
            config.startPrice > 0 &&
                config.priceAdjustInterval > 0 &&
                config.maxPrice > config.startPrice &&
                config.genisTime > 0 &&
                config.priceStep > 0,
            "INVALID_CONFIG"
        );

        paymentConfig = config;
        emit UpdatePaymentConfig(config);
    }

    function queryPaymentConfig()
        external
        view
        override
        returns (PaymentConfig memory)
    {
        return paymentConfig;
    }

    function queryReferenceConfig()
        external
        view
        override
        returns (ReferenceConfig memory)
    {
        return referenceConfig;
    }

    function queryMintConfig()
        external
        view
        override
        returns (MintConfig memory)
    {
        return mintConfig;
    }

    function queryReferralClaimRecords(uint256 tokenId)
        public
        view
        override
        returns (ReferralClaimRecord[] memory records)
    {
        records = _referralClaimRecords[tokenId];
    }

    function queryReferralItems(address referrer)
        public
        view
        override
        returns (Item[] memory items)
    {
        items = new Item[](_referralTokenIds[referrer].length());
        for (uint256 i; i < items.length; i++) {
            uint256 tokenId = _referralTokenIds[referrer].at(i);
            items[i] = _tokenIdItems[tokenId];
        }
    }

    function claimReferralReward(uint256 tokenId) external override {
        address referrer = msg.sender;
        require(
            _referralTokenIds[referrer].contains(tokenId),
            "INVALID_ACCESS"
        );
        ReferralClaimRecord[] memory records = _referralClaimRecords[tokenId];
        Item memory item = _tokenIdItems[tokenId];
        require(item.fee > 0, "INVALID_ITEM");
        require(
            records.length < referenceConfig.cliamCount,
            "NOTHIGN_TO_CLAIM"
        );
        uint256 claimableCount = (_currentTimestamp() - item.mintTime) /
            referenceConfig.cliamInterval;
        require(claimableCount > records.length, "NOT_CLAIM_TIME");
        uint256 amount = item.fee.multiplyDecimal(referenceConfig.rewardRate) /
            referenceConfig.cliamCount;
        if (item.currency == address(0)) {
            payable(referrer).transfer(amount);
        } else {
            IERC20(item.currency).transfer(referrer, amount);
        }
        _referralClaimRecords[tokenId].push(
            ReferralClaimRecord({amount: amount, time: _currentTimestamp()})
        );
    }

    function getVariableView()
        public
        view
        override
        returns (VariableView memory)
    {
        return
            VariableView({
                currency: paymentConfig.currency,
                startPrice: paymentConfig.startPrice,
                priceAdjustInterval: paymentConfig.priceAdjustInterval,
                maxPrice: paymentConfig.maxPrice,
                currentPrice: _price(),
                genisTime: paymentConfig.genisTime,
                maleInventory: mintConfig.maleMax -
                    _genderTokenIds[MALE].length(),
                femaleInventory: mintConfig.femaleMax -
                    _genderTokenIds[FEMALE].length()
            });
    }

    function _price() private view returns (uint256) {
        uint256 passedSeconds = _currentTimestamp() - paymentConfig.genisTime;
        uint256 price = paymentConfig.priceStep *
            (passedSeconds / paymentConfig.priceAdjustInterval) +
            paymentConfig.startPrice;

        if (price >= paymentConfig.maxPrice - paymentConfig.priceStep) {
            price = paymentConfig.maxPrice;
        }

        return price;
    }

    function keccak256MintArgs(address sender, address referral)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(sender, referral));
    }

    function getMintCount(address user) external view override returns (uint8) {
        return _userMintCounts[user];
    }

    function mint(
        bool isSuit,
        uint8 gender,
        uint8 nftCount,
        address referral,
        bytes memory signature
    ) external payable override returns (uint256 tokenId) {
        address buyer = msg.sender;
        _verifyMintArgs(buyer, referral, isSuit, gender, nftCount, signature);
        tokenId = nextTokenId++;

        _userMintCounts[buyer] += nftCount;

        _genderTokenIds[gender].add(tokenId);
        _mint(buyer, tokenId);

        uint256 fee = _price() * nftCount;

        _tokenIdItems[tokenId] = Item({
            tokenId: tokenId,
            referral: referral,
            buyer: buyer,
            fee: fee,
            currency: paymentConfig.currency,
            mintTime: _currentTimestamp(),
            isSuit: isSuit,
            gender: gender,
            nftCount: nftCount
        });

        if (referral != address(0)) {
            _referralTokenIds[referral].add(tokenId);
        }

        _transferFrom(paymentConfig.currency, buyer, fee);

        emit Mint(
            buyer,
            isSuit,
            gender,
            nftCount,
            paymentConfig.currency,
            fee,
            referral
        );
    }

    function keccak256OpenArgs(
        uint256 mysteryBoxId,
        address[] memory nfts,
        uint256[] memory nftTokenIds,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(mysteryBoxId, nfts, nftTokenIds, deadline)
            );
    }

    function open(
        uint256 tokenId,
        address[] memory nfts,
        uint256[] memory nftTokenIds,
        uint256 deadline,
        bytes memory signature
    ) external override {
        require(deadline > _currentTimestamp(), "EXPIRED");
        bytes32 argsHash = keccak256OpenArgs(
            tokenId,
            nfts,
            nftTokenIds,
            deadline
        );
        require(
            _signers.contains(Signature.getSigner(argsHash, signature)),
            "VERIFY_FAILED"
        );
        require(msg.sender == ownerOf(tokenId), "INVALID_ACCESS");
        Item memory item = _tokenIdItems[tokenId];
        require(item.nftCount == nfts.length, "INVALID_NFTS");
        require(item.nftCount == nftTokenIds.length, "INVALID_TOKEN_IDS");
        for (uint256 i; i < nfts.length; i++) {
            IKeplerNFT(nfts[i]).mintTo(msg.sender, nftTokenIds[i]);
        }
        _burn(tokenId);
        _genderTokenIds[item.gender].remove(tokenId);
        emit Open(msg.sender, tokenId, nfts, nftTokenIds);
    }

    function tokenIdsOfOwner(address owner)
        public
        view
        override
        returns (uint256[] memory tokenIds)
    {
        uint256 balance = balanceOf(owner);
        tokenIds = new uint256[](balance);
        for (uint256 i; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
    }

    function itemsOfOwner(address owner)
        external
        view
        override
        returns (Item[] memory items)
    {
        uint256[] memory tokenIds = tokenIdsOfOwner(owner);
        items = new Item[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            items[i] = _tokenIdItems[tokenIds[i]];
        }
    }

    function _currentTimestamp() private view returns (uint256) {
        return block.timestamp;
    }

    function allItems()
        external
        view
        override
        returns (ItemView[] memory items)
    {
        uint256 maleCount = _genderTokenIds[MALE].length();
        uint256 femaleCount = _genderTokenIds[FEMALE].length();
        items = new ItemView[](maleCount + femaleCount);
        uint256 index;

        for (uint256 i; i < maleCount; i++) {
            uint256 tokenId = _genderTokenIds[MALE].at(i);
            items[index] = _toItemView(tokenId, _tokenIdItems[tokenId]);
            index++;
        }

        for (uint256 i; i < femaleCount; i++) {
            uint256 tokenId = _genderTokenIds[FEMALE].at(i);
            items[index] = _toItemView(tokenId, _tokenIdItems[tokenId]);
            index++;
        }
    }

    function _verifyMintArgs(
        address buyer,
        address referral,
        bool isSuit,
        uint8 gender,
        uint8 nftCount,
        bytes memory signature
    ) private view {
        require(
            _signers.contains(
                Signature.getSigner(
                    keccak256MintArgs(buyer, referral),
                    signature
                )
            ),
            "VERIFY_FAILED"
        );
        if (isSuit) {
            require(nftCount == SUIT_PART_COUNT, "INVALID_NFT_COUNT");
        }
        require(
            _userMintCounts[buyer] + nftCount <= USER_MAX_MINT_COUNT,
            "EXCEED_MAX_MINT_COUNT"
        );

        uint256 maxCount = gender == FEMALE
            ? mintConfig.femaleMax
            : mintConfig.maleMax;

        require(
            _genderTokenIds[gender].length() + nftCount <= maxCount,
            "INSUFFICIENT_INVENTORY"
        );

        require(gender == FEMALE || gender == MALE, "INVALID_GENDER");
    }

    function _transferFrom(
        address currency,
        address from,
        uint256 fee
    ) private {
        if (currency == address(0)) {
            require(msg.value >= fee, "INVALID_MSG_VALUE");
        } else {
            IERC20 erc20 = IERC20(currency);
            require(erc20.balanceOf(from) >= fee, "INSUFICIENT_BALANCE");
            require(
                erc20.allowance(from, address(this)) >= fee,
                "INSUFICIENT_ALLOWANCE"
            );
            erc20.transferFrom(from, address(this), fee);
        }
    }

    function _toItemView(uint256 tokenId, Item memory item)
        private
        pure
        returns (ItemView memory)
    {
        return
            ItemView({
                tokenId: tokenId,
                isSuit: item.isSuit,
                gender: item.gender,
                nftCount: item.nftCount,
                user: item.buyer,
                fee: item.fee
            });
    }
}
