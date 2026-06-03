// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice NFTMarket — 基于 IERC721Receiver 的 NFT 市场合约。
///         卖家将 NFT 托管至合约（托管模式），买家使用 BIT 代币购买。
///         市场方可设置手续费比例（基点）和手续费接收地址。
contract NFTMarket is IERC721Receiver, ERC165, Ownable {
    // =============================================================
    // 类型定义
    // =============================================================

    /// @notice 上架信息
    /// @param seller 卖家地址
    /// @param price  售价（BIT 代币最小单位）
    /// @param nft    NFT 合约地址（支持多 NFT 合集）
    /// @param active 是否仍在售
    struct Listing {
        address seller;
        uint256 price;
        IERC721 nft;
        bool active;
    }

    // =============================================================
    // 状态变量
    // =============================================================

    /// @notice 支付代币（BIT）
    IERC20 public immutable paymentToken;

    /// @notice 手续费比例，单位为基点（例如 250 = 2.5%，10000 = 100%）
    uint256 public feeBps;

    /// @notice 手续费接收地址
    address public feeRecipient;

    /// @notice NFT 合约 => tokenId => Listing
    /// @dev  先按 NFT 合约地址，再按 tokenId 组合定位，避免不同合集 tokenId 冲突
    mapping(IERC721 nft => mapping(uint256 tokenId => Listing)) private _listings;

    // =============================================================
    // 事件
    // =============================================================

    event Listed(
        address indexed seller,
        IERC721 indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );

    event Sold(
        address indexed seller,
        address indexed buyer,
        IERC721 indexed nft,
        uint256 tokenId,
        uint256 price,
        uint256 fee
    );

    event Cancelled(
        address indexed seller,
        IERC721 indexed nft,
        uint256 indexed tokenId
    );

    event FeeUpdated(uint256 newFeeBps, address newFeeRecipient);

    // =============================================================
    // 构造器
    // =============================================================

    /// @param paymentToken_  支付代币地址（BrianICOToken / BIT）
    /// @param feeBps_        初始手续费基点（0 表示无手续费）
    /// @param feeRecipient_  手续费接收地址
    constructor(
        address paymentToken_,
        uint256 feeBps_,
        address feeRecipient_
    ) Ownable(msg.sender) {
        require(paymentToken_ != address(0), "Market: zero payment token");
        require(feeBps_ <= 10000, "Market: fee exceeds 100%");
        require(feeRecipient_ != address(0), "Market: zero fee recipient");

        paymentToken = IERC20(paymentToken_);
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
    }

    // =============================================================
    // 上架 / 下架 / 购买
    // =============================================================

    /// @notice 上架一枚 NFT 到市场（NFT 将被转入本合约托管）
    /// @param nft     NFT 合约地址
    /// @param tokenId NFT token ID
    /// @param price   售价（BIT 代币最小单位），须 > 0
    function list(IERC721 nft, uint256 tokenId, uint256 price) external {
        require(price > 0, "Market: price must be > 0");
        require(nft.ownerOf(tokenId) == msg.sender, "Market: not owner");
        require(!_listings[nft][tokenId].active, "Market: already listed");

        // 将 NFT 转入本合约托管
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        _listings[nft][tokenId] = Listing({
            seller: msg.sender,
            price: price,
            nft: nft,
            active: true
        });

        emit Listed(msg.sender, nft, tokenId, price);
    }

    /// @notice 购买一枚已上架的 NFT
    /// @dev 买家需先 approve 足够的 BIT 给本合约
    /// @param nft     NFT 合约地址
    /// @param tokenId NFT token ID
    function buy(IERC721 nft, uint256 tokenId) external {
        Listing storage listing = _listings[nft][tokenId];
        require(listing.active, "Market: not listed");
        require(listing.seller != msg.sender, "Market: cannot buy own");

        address seller = listing.seller;
        uint256 price = listing.price;

        // 计算手续费和卖家所得
        uint256 fee = (price * feeBps) / 10000;
        uint256 sellerProceeds = price - fee;

        // 清除上架信息（防止重入）
        delete _listings[nft][tokenId];

        // 转账支付代币：买家 → 卖家（扣除手续费）
        require(
            paymentToken.transferFrom(msg.sender, seller, sellerProceeds),
            "Market: payment to seller failed"
        );
        // 手续费：买家 → 手续费接收方
        if (fee > 0) {
            require(
                paymentToken.transferFrom(msg.sender, feeRecipient, fee),
                "Market: fee transfer failed"
            );
        }

        // 将 NFT 从本合约转给买家
        nft.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Sold(seller, msg.sender, nft, tokenId, price, fee);
    }

    /// @notice 卖家取消上架，取回 NFT
    /// @param nft     NFT 合约地址
    /// @param tokenId NFT token ID
    function cancel(IERC721 nft, uint256 tokenId) external {
        Listing storage listing = _listings[nft][tokenId];
        require(listing.active, "Market: not listed");
        require(listing.seller == msg.sender, "Market: not seller");

        address seller = listing.seller;
        delete _listings[nft][tokenId];

        // 将 NFT 退回给卖家
        nft.safeTransferFrom(address(this), seller, tokenId);

        emit Cancelled(seller, nft, tokenId);
    }

    // =============================================================
    // Owner 管理
    // =============================================================

    /// @notice 更新手续费参数
    /// @param newFeeBps      新的手续费基点
    /// @param newFeeRecipient 新的手续费接收地址
    function setFee(uint256 newFeeBps, address newFeeRecipient) external onlyOwner {
        require(newFeeBps <= 10000, "Market: fee exceeds 100%");
        require(newFeeRecipient != address(0), "Market: zero fee recipient");
        feeBps = newFeeBps;
        feeRecipient = newFeeRecipient;
        emit FeeUpdated(newFeeBps, newFeeRecipient);
    }

    // =============================================================
    // 只读函数
    // =============================================================

    /// @notice 查询某枚 NFT 的上架信息
    /// @param nft     NFT 合约地址
    /// @param tokenId NFT token ID
    /// @return seller 卖家地址
    /// @return price  售价
    /// @return active 是否在售
    function getListing(
        IERC721 nft,
        uint256 tokenId
    ) external view returns (address seller, uint256 price, bool active) {
        Listing storage listing = _listings[nft][tokenId];
        return (listing.seller, listing.price, listing.active);
    }

    // =============================================================
    // IERC721Receiver
    // =============================================================

    /// @notice 接收 ERC721 安全转账的回调
    /// @dev 仅返回 selector，表示接受所有 ERC721 转入
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // =============================================================
    // ERC165
    // =============================================================

    /// @notice 检查合约是否支持指定接口
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
