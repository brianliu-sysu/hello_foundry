// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice BrianNFT — 一个可枚举、带独立 URI 的 NFT 合约，仅 owner 可铸造。
contract BrianNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    // =============================================================
    // 状态变量
    // =============================================================

    /// @notice 下一个可铸造的 token ID（从 1 开始递增）
    uint256 private _nextTokenId;

    /// @notice 最大供应量（0 表示无上限）
    uint256 public maxSupply;

    /// @notice 基础 URI，所有 tokenURI 的前缀
    string private _baseTokenURI;

    // =============================================================
    // 事件
    // =============================================================

    event Minted(address indexed to, uint256 indexed tokenId, string uri);
    event BaseURIUpdated(string newBaseURI);
    event MaxSupplyUpdated(uint256 newMaxSupply);

    // =============================================================
    // 构造器
    // =============================================================

    /// @param name_         NFT 名称
    /// @param symbol_       NFT 符号
    /// @param baseTokenURI_ 基础元数据 URI
    /// @param maxSupply_    最大供应量，0 表示无上限
    constructor(string memory name_, string memory symbol_, string memory baseTokenURI_, uint256 maxSupply_)
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {
        _baseTokenURI = baseTokenURI_;
        maxSupply = maxSupply_;
    }

    // =============================================================
    // 铸造
    // =============================================================

    /// @notice 由 owner 铸造一枚 NFT 给指定地址
    /// @param to    接收者地址
    /// @param uri   该 token 的元数据 URI（相对于 baseURI）
    /// @return tokenId 铸造出的 token ID
    function safeMint(address to, string memory uri) public onlyOwner returns (uint256) {
        return _mintToken(to, uri);
    }

    /// @notice 批量铸造，owner 一次为多个地址各铸造一枚
    /// @param recipients 接收者地址列表
    /// @param uris      每个接收者对应的 URI 列表，长度须与 recipients 一致
    function safeMintBatch(address[] calldata recipients, string[] calldata uris) external onlyOwner {
        require(recipients.length == uris.length, "BrianNFT: length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _mintToken(recipients[i], uris[i]);
        }
    }

    /// @dev 内部铸造逻辑
    function _mintToken(address to, string memory uri) internal returns (uint256 tokenId) {
        require(maxSupply == 0 || _nextTokenId < maxSupply, "BrianNFT: max supply reached");

        _nextTokenId++;
        tokenId = _nextTokenId;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit Minted(to, tokenId, uri);
    }

    // =============================================================
    // Owner 管理函数
    // =============================================================

    /// @notice 更新基础 URI
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /// @notice 更新最大供应量（不可低于已铸造量）
    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        require(newMaxSupply == 0 || newMaxSupply >= _nextTokenId, "BrianNFT: below minted");
        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    // =============================================================
    // 只读函数
    // =============================================================

    /// @notice 返回下一个可铸造的 token ID
    function nextTokenId() public view returns (uint256) {
        return _nextTokenId + 1;
    }

    /// @notice 返回已铸造总量
    function totalMinted() public view returns (uint256) {
        return _nextTokenId;
    }

    // =============================================================
    // 内部重写（多继承 Diamond 继承线性化）
    // =============================================================

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
