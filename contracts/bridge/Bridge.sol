
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../nft/interfaces/IKeplerNFT.sol";
import "../tokens/interfaces/IToken.sol";
import "../libraries/Signature.sol";
import "./interfaces/IBridge.sol";

contract Bridge is IBridge, OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => mapping(address => EnumerableSet.UintSet))
        private _userNFTs;

    mapping(address => mapping(address => uint256)) private _userTokens;

    EnumerableSet.AddressSet private _signers;
    EnumerableSet.AddressSet private _supportedNFTs;
    EnumerableSet.AddressSet private _supportedTokens;
    EnumerableSet.UintSet private _orderIds;

    address public override feeToken;

    mapping(uint256 => TokenOrder) private _tokenApplyOrders;
    mapping(uint256 => TokenOrder) private _tokenClaimOrders;
    mapping(uint256 => NFTOrder) private _nftApplyOrders;
    mapping(uint256 => NFTOrder) private _nftClaimOrders;

    function initialize(address signer_, address feeToken_) public initializer {
        __Ownable_init();
        _signers.add(signer_);
        feeToken = feeToken_;
    }

    function keccak256String(string memory val) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(val));
    }

    function keccak256ApplyTokenArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromNFT,
        uint256 amount,
        uint256 toChainId,
        uint256 fee,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderId,
                    applicant,
                    receipient,
                    fromChainId,
                    fromNFT,
                    amount,
                    toChainId,
                    fee,
                    deadline
                )
            );
    }

    function applyToken(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromToken,
        uint256 amount,
        uint256 toChainId,
        uint256 fee,
        uint256 deadline,
        bytes memory signature
    ) external payable override {
        require(deadline > block.timestamp, "EXPIRED");
        bytes32 argsHash = keccak256ApplyTokenArgs(
            orderId,
            applicant,
            receipient,
            fromChainId,
            fromToken,
            amount,
            toChainId,
            fee,
            deadline
        );

        require(
            _signers.contains(Signature.getSigner(argsHash, signature)),
            "VERIFY_FAILED"
        );

        require(_supportedTokens.contains(fromToken), "UNSUPPORTED_TOKEN");
        require(applicant == msg.sender, "INVALID_APPLICANT");
        require(!_orderIds.contains(orderId), "ORDER_ID_EXISTS");
        _orderIds.add(orderId);

        _tansferFee(fee);

        _userTokens[applicant][fromToken] += amount;
        _tokenApplyOrders[orderId] = TokenOrder(
            applicant,
            receipient,
            fromToken,
            amount
        );
        IToken(fromToken).transferFrom(applicant, address(this), amount);
        emit ApplyToken(
            orderId,
            applicant,
            receipient,
            fromChainId,
            fromToken,
            amount,
            toChainId,
            fee
        );
    }

    function _tansferFee(uint256 fee) private {
        if (feeToken == address(0)) {
            require(msg.value >= fee, "INSUFFICIENT_FEE");
        } else {
            require(
                IERC20(feeToken).balanceOf(msg.sender) >= fee,
                "INSUFFICIENT_FEE_TOKEN_BALANCE"
            );
            require(
                IERC20(feeToken).allowance(msg.sender, address(this)) >= fee,
                "INSUFFICIENT_FEE_TOKEN_ALLOWANCE"
            );
            IERC20(feeToken).transferFrom(msg.sender, address(this), fee);
        }
    }

    function keccak256ApplyNFTArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromNFT,
        uint256[] memory fromTokenIds,
        uint256 toChainId,
        uint256 fee,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderId,
                    applicant,
                    receipient,
                    fromChainId,
                    fromNFT,
                    fromTokenIds,
                    toChainId,
                    fee,
                    deadline
                )
            );
    }

    function applyNFT(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromNFT,
        uint256[] memory fromTokenIds,
        uint256 toChainId,
        uint256 fee,
        uint256 deadline,
        bytes memory signature
    ) external payable override {
        require(deadline > block.timestamp, "EXPIRED");
        bytes32 argsHash = keccak256ApplyNFTArgs(
            orderId,
            applicant,
            receipient,
            fromChainId,
            fromNFT,
            fromTokenIds,
            toChainId,
            fee,
            deadline
        );
        require(
            _signers.contains(Signature.getSigner(argsHash, signature)),
            "VERIFY_FAILED"
        );
        require(_supportedNFTs.contains(fromNFT), "UNSUPPORTED_NFT");
        require(applicant == msg.sender, "INVALID_APPLICANT");
        require(!_orderIds.contains(orderId), "ORDER_ID_EXISTS");
        _orderIds.add(orderId);
        _nftApplyOrders[orderId] = NFTOrder(
            applicant,
            receipient,
            fromNFT,
            fromTokenIds
        );

        _tansferFee(fee);

        for (uint256 i; i < fromTokenIds.length; i++) {
            uint256 tokenId = fromTokenIds[i];
            _userNFTs[applicant][fromNFT].add(tokenId);
            IKeplerNFT(fromNFT).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }

        emit ApplyNFT(
            orderId,
            applicant,
            receipient,
            fromChainId,
            fromNFT,
            fromTokenIds,
            toChainId,
            fee
        );
    }

    function keccak256ClaimNFTArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toNFT,
        uint256[] memory tokenIds,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderId,
                    applicant,
                    receipient,
                    toChainId,
                    toNFT,
                    tokenIds,
                    deadline
                )
            );
    }

    function claimNFT(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toNFT,
        uint256[] memory tokenIds,
        uint256 deadline,
        bytes memory signature
    ) external override {
        require(deadline > block.timestamp, "EXPIRED");
        bytes32 argsHash = keccak256ClaimNFTArgs(
            orderId,
            applicant,
            receipient,
            toChainId,
            toNFT,
            tokenIds,
            deadline
        );

        require(
            _signers.contains(Signature.getSigner(argsHash, signature)),
            "VERIFY_FAILED"
        );

        require(
            msg.sender == applicant || msg.sender == receipient,
            "ACCESS_DENIED"
        );
        require(!_orderIds.contains(orderId), "ORDER_ID_EXISTS");
        _orderIds.add(orderId);
        require(_supportedNFTs.contains(toNFT), "UNSUPPORTED_NFT");

        for (uint256 i; i < tokenIds.length; i++) {
            IKeplerNFT nft = IKeplerNFT(toNFT);
            uint256 tokenId = tokenIds[i];
            if (nft.exists(tokenId)) {
                require(
                    nft.ownerOf(tokenId) == address(this),
                    "INVALID_NFT_OWNER"
                );
                nft.transferFrom(address(this), receipient, tokenId);
            } else {
                nft.mintTo(receipient, tokenId);
            }
        }
        _nftClaimOrders[orderId] = NFTOrder(
            applicant,
            receipient,
            toNFT,
            tokenIds
        );
        emit ClaimNFT(
            orderId,
            applicant,
            receipient,
            toChainId,
            toNFT,
            tokenIds
        );
    }

    function keccak256ClaimTokenArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256 amount,
        uint256 deadline
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    orderId,
                    applicant,
                    receipient,
                    toChainId,
                    toToken,
                    amount,
                    deadline
                )
            );
    }

    function claimToken(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256 amount,
        uint256 deadline,
        bytes memory signature
    ) external override {
        require(deadline > block.timestamp, "EXPIRED");
        bytes32 argsHash = keccak256ClaimTokenArgs(
            orderId,
            applicant,
            receipient,
            toChainId,
            toToken,
            amount,
            deadline
        );
        require(
            _signers.contains(Signature.getSigner(argsHash, signature)),
            "VERIFY_FAILED"
        );

        require(
            msg.sender == applicant || msg.sender == receipient,
            "ACCESS_DENIED"
        );
        require(!_orderIds.contains(orderId), "ORDER_ID_EXISTS");
        _orderIds.add(orderId);
        _tokenClaimOrders[orderId] = TokenOrder(
            applicant,
            receipient,
            toToken,
            amount
        );

        require(_supportedTokens.contains(toToken), "UNSUPPORTED_TOKEN");

        IToken(toToken).mint(receipient, amount);
        emit ClaimToken(
            orderId,
            applicant,
            receipient,
            toChainId,
            toToken,
            amount
        );
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

    function addSupportedTokens(address[] memory items) public onlyOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _supportedTokens.add(items[i]);
        }
    }

    function removeSupportedTokens(address[] memory items) public onlyOwner {
        for (uint256 i = 0; i < items.length; i++) {
            _supportedTokens.remove(items[i]);
        }
    }

    function getSupportedTokens()
        external
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](_supportedTokens.length());
        for (uint256 i; i < tokens.length; i++) {
            tokens[i] = _supportedTokens.at(i);
        }
    }

    function getTokenApplyOrder(uint256 orderId)
        external
        view
        override
        returns (TokenOrder memory)
    {
        return _tokenApplyOrders[orderId];
    }

    function getTokenClaimOrder(uint256 orderId)
        external
        view
        override
        returns (TokenOrder memory)
    {
        return _tokenClaimOrders[orderId];
    }

    function getNFTApplyOrder(uint256 orderId)
        external
        view
        override
        returns (NFTOrder memory)
    {
        return _nftApplyOrders[orderId];
    }

    function getNFTClaimOrder(uint256 orderId)
        external
        view
        override
        returns (NFTOrder memory)
    {
        return _nftClaimOrders[orderId];
    }
}
