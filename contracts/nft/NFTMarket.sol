
pragma solidity ^0.8.4;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/SafeDecimalMath.sol";
import "../libraries/Signature.sol";
import "../swap/libraries/TransferHelper.sol";
import "../common/IWOKT.sol";
import "./interfaces/INFTMarket.sol";
import "./interfaces/IKeplerNFT.sol";

contract NFTMarket is
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    INFTMarket
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    address public signer;

    uint8 public constant STATUS_OPEN = 1;
    uint8 public constant STATUS_SUCCESS = 2;
    uint8 public constant STATUS_CLOSE = 3;

    address public weth;
    address public feeWallet;

    mapping(uint256 => Item) private _items;
    EnumerableSet.UintSet private _itemIds;
    EnumerableSet.AddressSet private _supportedCurrencies;
    EnumerableSet.AddressSet private _supportedNFTs;
    mapping(uint256 => EnumerableSet.UintSet) private _statusItemMap;

    function initialize(address signer_, address feeWallet_)
        public
        initializer
    {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        signer = signer_;
        feeWallet = feeWallet_;
        _supportedCurrencies.add(address(0));
    }

    function addSupportedNFTs(address[] memory items) public onlyOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _supportedNFTs.add(items[i]);
        }
    }

    function removeSupportedNFTs(address[] memory items) public onlyOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _supportedNFTs.remove(items[i]);
        }
    }

    function addSupportedCurrencies(address[] memory items) public onlyOwner {
        for (uint256 i; i < items.length; i++) {
            _supportedCurrencies.add(items[i]);
        }
    }

    function removeSupportedCurrencies(address[] memory items)
        public
        onlyOwner
    {
        for (uint256 i; i < items.length; i++) {
            _supportedCurrencies.remove(items[i]);
        }
    }

    function setFeeWallet(address val) public onlyOwner {
        feeWallet = val;
    }

    function getItem(uint256 itemId)
        external
        view
        override
        returns (Item memory)
    {
        return _items[itemId];
    }

    function close(uint256 itemId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        Item memory item = _items[itemId];
        require(item.status == STATUS_OPEN, "ITEM_STATUS_NOT_OPEN");
        require(
            item.seller == msg.sender || msg.sender == owner(),
            "UNAUTHORIZED"
        );
        _statusItemMap[item.status].remove(item.id);

        IERC721Metadata(item.nft).transferFrom(
            address(this),
            item.seller,
            item.tokenId
        );
        item.status = STATUS_CLOSE;
        _statusItemMap[item.status].add(item.id);
        _items[itemId] = item;
        emit Close(itemId);
    }

    function encode(
        uint256 id,
        address nft,
        uint256 tokenId,
        address currency,
        uint256 price,
        uint256 fee,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    id,
                    nft,
                    tokenId,
                    currency,
                    price,
                    fee,
                    deadline
                )
            );
    }

    function open(
        uint256 id,
        address nft,
        uint256 tokenId,
        address currency,
        uint256 price,
        uint256 fee,
        uint256 deadline,
        bytes memory signature
    ) external override nonReentrant whenNotPaused {
        require(deadline > block.timestamp, "EXPIRED");
        require(tokenId != 0, "INVALID_TOKEN_ID");
        require(price > 0, "INVALID_PRICE");
        require(_supportedNFTs.contains(nft), "UNSUPPORTED_NFT");
        require(
            _supportedCurrencies.contains(currency),
            "UNSUPPORTED_CURRENCY"
        );
        require(
            Signature.getSigner(
                encode(id, nft, tokenId, currency, price, fee, deadline),
                signature
            ) == signer,
            "VERIFY_FAILED"
        );

        require(
            IKeplerNFT(nft).isApprovedForAll(msg.sender, address(this)) ||
                IKeplerNFT(nft).getApproved(tokenId) == address(this),
            "NOT_APPROVED"
        );

        IKeplerNFT(nft).transferFrom(msg.sender, address(this), tokenId);

        Item memory item;
        item.status = STATUS_OPEN;
        item.id = id;
        item.nft = nft;
        item.tokenId = tokenId;
        item.currency = currency;
        item.price = price;
        item.fee = fee;
        item.seller = msg.sender;
        _itemIds.add(item.id);
        _items[item.id] = item;
        _statusItemMap[item.status].add(item.id);

        emit Open(id, nft, tokenId, currency, price, fee);
    }

    function buy(uint256 itemId)
        external
        payable
        override
        nonReentrant
        whenNotPaused
    {
        Item memory item = _items[itemId];
        require(item.status == STATUS_OPEN, "ITEM_STATUS_NOT_OPEN");
        _statusItemMap[item.status].remove(item.id);
        uint256 price = item.price;
        item.status = STATUS_SUCCESS;
        item.buyer = msg.sender;
        _items[itemId] = item;
        _statusItemMap[item.status].add(item.id);

        uint256 fee = item.fee;
        uint256 purchase = price.sub(fee);
        if (item.currency == address(0)) {
            require(msg.value == price, "INVALID_WETH_AMOUNT");
            payable(item.seller).transfer(purchase);
        } else {
            IERC20(item.currency).transferFrom(msg.sender, feeWallet, fee);
            IERC20(item.currency).transferFrom(
                msg.sender,
                item.seller,
                purchase
            );
        }

        IERC721Metadata(item.nft).transferFrom(
            address(this),
            msg.sender,
            item.tokenId
        );

        emit Buy(itemId, msg.sender, item.price, item.fee);
    }

    function getItems(uint8 status)
        external
        view
        override
        returns (Item[] memory items)
    {
        items = new Item[](_statusItemMap[status].length());
        for (uint256 i; i < items.length; i++) {
            items[i] = _items[_statusItemMap[STATUS_OPEN].at(i)];
        }
    }

    function getSupportedCurrencies()
        external
        view
        override
        returns (address[] memory currencies)
    {
        currencies = new address[](_supportedCurrencies.length());
        for (uint256 i; i < currencies.length; i++) {
            currencies[i] = _supportedCurrencies.at(i);
        }
    }

    function getSupportedNFTs()
        external
        view
        override
        returns (address[] memory nfts)
    {
        nfts = new address[](_supportedNFTs.length());
        for (uint256 i; i < nfts.length; i++) {
            nfts[i] = _supportedNFTs.at(i);
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        if (address(this) != operator) {
            return 0;
        }
        emit NFTReceived(operator, from, tokenId, data);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
