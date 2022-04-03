
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../common/Minable.sol";
import "./interfaces/IKeplerNFT.sol";

abstract contract KeplerNFT is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    Minable,
    IKeplerNFT
{
    using Strings for uint256;
    string public baseURI;

    function __KeplerNFT_init(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) public virtual initializer {
        __Ownable_init();
        __ERC721_init(name_, symbol_);
        baseURI = baseURI_;
        addMinter(msg.sender);
    }

    function updateBaseURI(string memory val) public onlyOwner {
        baseURI = val;
    }

    function mintTo(address to, uint256 tokenId)
        public
        virtual
        override
        onlyMinter
    {
        _mint(to, tokenId);
    }

    function batchMintTo(address to, uint256[] memory tokenIds)
        public
        onlyMinter
    {
        _batchMintTo(to, tokenIds);
    }

    function burn(uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(_msgSender() == owner, "caller is not the token owner");
        _burn(tokenId);
    }

    function tokensOfOwner(address owner)
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

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC721MetadataUpgradeable)
        returns (string memory)
    {
        require(_exists(tokenId), "INVALID_TOKEN_ID");
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function _batchMintTo(address to, uint256[] memory tokenIds) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _mint(to, tokenIds[i]);
        }
    }

    function exists(uint256 tokenId) external view override returns (bool) {
        return _exists(tokenId);
    }
}
