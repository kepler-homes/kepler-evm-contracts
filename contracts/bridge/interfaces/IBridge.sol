
pragma solidity ^0.8.4;

interface IBridge {
    event ApplyNFT(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromNFT,
        uint256[] fromTokenIds,
        uint256 toChainId,
        uint256 fee
    );

    event ClaimNFT(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256[] toTokenIds
    );

    event ApplyToken(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromToken,
        uint256 amount,
        uint256 toChainId,
        uint256 fee
    );

    event ClaimToken(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256 amount
    );

    struct TokenOrder {
        address applicant;
        address receipient;
        address token;
        uint256 amount;
    }

    struct NFTOrder {
        address applicant;
        address receipient;
        address nft;
        uint256[] tokenIds;
    }

    function getTokenApplyOrder(uint256 orderId)
        external
        view
        returns (TokenOrder memory);

    function getTokenClaimOrder(uint256 orderId)
        external
        view
        returns (TokenOrder memory);

    function getNFTApplyOrder(uint256 orderId)
        external
        view
        returns (NFTOrder memory);

    function getNFTClaimOrder(uint256 orderId)
        external
        view
        returns (NFTOrder memory);

    function feeToken() external view returns (address);

    function getSupportedNFTs() external view returns (address[] memory nfts);

    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens);

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
    ) external pure returns (bytes32);

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
    ) external payable;

    function keccak256ClaimNFTArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toNFT,
        uint256[] memory tokenIds,
        uint256 deadline
    ) external pure returns (bytes32);

    function claimNFT(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toNFT,
        uint256[] memory tokenIds,
        uint256 deadline,
        bytes memory signature
    ) external;

    function keccak256ApplyTokenArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 fromChainId,
        address fromToken,
        uint256 amount,
        uint256 toChainId,
        uint256 fee,
        uint256 deadline
    ) external pure returns (bytes32);

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
    ) external payable;

    function keccak256ClaimTokenArgs(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256 amount,
        uint256 deadline
    ) external pure returns (bytes32);

    function claimToken(
        uint256 orderId,
        address applicant,
        address receipient,
        uint256 toChainId,
        address toToken,
        uint256 amount,
        uint256 deadline,
        bytes memory signature
    ) external;
}
