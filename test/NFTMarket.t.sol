// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianNFT} from "../src/BrianNFT.sol";
import {BrianICOToken} from "../src/BrianICOToken.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTMarketTest is Test {
    BrianNFT public nft;
    BrianICOToken public bit;
    NFTMarket public market;

    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public other = makeAddr("other");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 100 万 BIT
    uint256 constant FEE_BPS = 250; // 2.5%
    string constant BASE_URI = "https://metadata.example.com/token/";

    event Listed(
        address indexed seller,
        BrianNFT indexed nft,
        uint256 indexed tokenId,
        uint256 price
    );
    event Sold(
        address indexed seller,
        address indexed buyer,
        BrianNFT indexed nft,
        uint256 tokenId,
        uint256 price,
        uint256 fee
    );
    event Cancelled(
        address indexed seller,
        BrianNFT indexed nft,
        uint256 indexed tokenId
    );
    event FeeUpdated(uint256 newFeeBps, address newFeeRecipient);

    function setUp() public {
        // 部署 NFT 合约（owner 铸造权限）
        vm.prank(owner);
        nft = new BrianNFT("BrianNFT", "BNFT", BASE_URI, 100);

        // 部署 BIT 代币，初始供应给 buyer 和 seller
        vm.prank(owner);
        bit = new BrianICOToken(INITIAL_SUPPLY);

        // 给 buyer 和 seller 转 BIT
        vm.prank(owner);
        bit.transfer(buyer, 100_000 * 10 ** 18);
        vm.prank(owner);
        bit.transfer(seller, 10_000 * 10 ** 18);

        // 部署市场合约
        vm.prank(owner);
        market = new NFTMarket(address(bit), FEE_BPS, feeRecipient);

        // 给 seller 铸造一枚 NFT（tokenId = 1）
        vm.prank(owner);
        nft.safeMint(seller, "1.json");
    }

    // =============================================================
    // 部署
    // =============================================================

    function test_Deploy_ParamsSet() public view {
        assertEq(address(market.paymentToken()), address(bit));
        assertEq(market.feeBps(), FEE_BPS);
        assertEq(market.feeRecipient(), feeRecipient);
        assertEq(market.owner(), owner);
    }

    function test_Deploy_RevertsZeroPaymentToken() public {
        vm.prank(owner);
        vm.expectRevert("Market: zero payment token");
        new NFTMarket(address(0), 0, feeRecipient);
    }

    function test_Deploy_RevertsFeeExceeds100Percent() public {
        vm.prank(owner);
        vm.expectRevert("Market: fee exceeds 100%");
        new NFTMarket(address(bit), 10001, feeRecipient);
    }

    function test_Deploy_RevertsZeroFeeRecipient() public {
        vm.prank(owner);
        vm.expectRevert("Market: zero fee recipient");
        new NFTMarket(address(bit), 0, address(0));
    }

    function test_Deploy_SupportsERC721Receiver() public view {
        assertTrue(
            market.supportsInterface(type(IERC721Receiver).interfaceId)
        );
    }

    // =============================================================
    // list（上架）
    // =============================================================

    function test_List_TransfersNFTToMarket() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        // NFT 已转入市场合约
        assertEq(nft.ownerOf(1), address(market));

        // 上架信息正确
        (address listedSeller, uint256 price, bool active) = market.getListing(nft, 1);
        assertEq(listedSeller, seller);
        assertEq(price, 1000 ether);
        assertTrue(active);
    }

    function test_List_EmitsEvent() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);

        vm.expectEmit(true, true, true, true);
        emit Listed(seller, nft, 1, 1000 ether);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();
    }

    function test_List_RevertsWhenPriceZero() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        vm.expectRevert("Market: price must be > 0");
        market.list(nft, 1, 0);
        vm.stopPrank();
    }

    function test_List_RevertsWhenNotOwner() public {
        vm.prank(buyer);
        vm.expectRevert("Market: not owner");
        market.list(nft, 1, 1000 ether);
    }

    function test_List_RevertsWhenAlreadyListed() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);

        // try to list again (should fail since market now owns it)
        vm.expectRevert("Market: not owner");
        market.list(nft, 1, 500 ether);
        vm.stopPrank();
    }

    // =============================================================
    // buy（购买）
    // =============================================================

    function test_Buy_TransfersNFTAndPayment() public {
        uint256 price = 1000 ether;
        uint256 expectedFee = (price * FEE_BPS) / 10000; // 25 ether
        uint256 sellerProceeds = price - expectedFee; // 975 ether

        // seller 上架
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, price);
        vm.stopPrank();

        uint256 sellerBalBefore = bit.balanceOf(seller);
        uint256 buyerBalBefore = bit.balanceOf(buyer);
        uint256 feeRecipientBalBefore = bit.balanceOf(feeRecipient);

        // buyer 购买
        vm.startPrank(buyer);
        bit.approve(address(market), price);
        market.buy(nft, 1);
        vm.stopPrank();

        // NFT 归属 buyer
        assertEq(nft.ownerOf(1), buyer);

        // 支付代币流转正确
        assertEq(bit.balanceOf(seller), sellerBalBefore + sellerProceeds);
        assertEq(bit.balanceOf(buyer), buyerBalBefore - price);
        assertEq(bit.balanceOf(feeRecipient), feeRecipientBalBefore + expectedFee);
    }

    function test_Buy_ListingClearedAfterSale() public {
        uint256 price = 1000 ether;

        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        bit.approve(address(market), price);
        market.buy(nft, 1);
        vm.stopPrank();

        // 上架信息已清除
        (, , bool active) = market.getListing(nft, 1);
        assertFalse(active);
    }

    function test_Buy_EmitsSoldEvent() public {
        uint256 price = 1000 ether;
        uint256 expectedFee = (price * FEE_BPS) / 10000;

        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        bit.approve(address(market), price);

        vm.expectEmit(true, true, true, true);
        emit Sold(seller, buyer, nft, 1, price, expectedFee);
        market.buy(nft, 1);
        vm.stopPrank();
    }

    function test_Buy_RevertsWhenNotListed() public {
        vm.prank(buyer);
        vm.expectRevert("Market: not listed");
        market.buy(nft, 1);
    }

    function test_Buy_RevertsWhenSellerBuysOwn() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        vm.startPrank(seller);
        bit.approve(address(market), 1000 ether);
        vm.expectRevert("Market: cannot buy own");
        market.buy(nft, 1);
        vm.stopPrank();
    }

    function test_Buy_RevertsWhenInsufficientAllowance() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        // buyer 没有 approve 足够的 BIT
        vm.startPrank(buyer);
        bit.approve(address(market), 100 ether); // 只 approve 100，需要 1000
        vm.expectRevert(); // ERC20: insufficient allowance
        market.buy(nft, 1);
        vm.stopPrank();
    }

    // =============================================================
    // cancel（取消上架）
    // =============================================================

    function test_Cancel_ReturnsNFTToSeller() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), address(market));

        // 取消上架
        vm.prank(seller);
        market.cancel(nft, 1);

        // NFT 退回 seller
        assertEq(nft.ownerOf(1), seller);

        // 上架信息已清除
        (, , bool active) = market.getListing(nft, 1);
        assertFalse(active);
    }

    function test_Cancel_EmitsCancelledEvent() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Cancelled(seller, nft, 1);
        vm.prank(seller);
        market.cancel(nft, 1);
    }

    function test_Cancel_RevertsWhenNotListed() public {
        vm.prank(seller);
        vm.expectRevert("Market: not listed");
        market.cancel(nft, 1);
    }

    function test_Cancel_RevertsWhenNotSeller() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(nft, 1, 1000 ether);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert("Market: not seller");
        market.cancel(nft, 1);
    }

    // =============================================================
    // 手续费管理
    // =============================================================

    function test_SetFee_UpdatesParams() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        market.setFee(500, newRecipient);

        assertEq(market.feeBps(), 500);
        assertEq(market.feeRecipient(), newRecipient);
    }

    function test_SetFee_EmitsFeeUpdatedEvent() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(500, newRecipient);

        vm.prank(owner);
        market.setFee(500, newRecipient);
    }

    function test_SetFee_RevertsWhenNotOwner() public {
        vm.prank(seller);
        vm.expectRevert(); // Ownable: caller is not the owner
        market.setFee(0, feeRecipient);
    }

    function test_SetFee_RevertsFeeExceeds100Percent() public {
        vm.prank(owner);
        vm.expectRevert("Market: fee exceeds 100%");
        market.setFee(10001, feeRecipient);
    }

    function test_SetFee_RevertsZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert("Market: zero fee recipient");
        market.setFee(0, address(0));
    }

    // =============================================================
    // 零手续费场景
    // =============================================================

    function test_ZeroFee_AllProceedsToSeller() public {
        // 部署零手续费市场
        vm.prank(owner);
        NFTMarket zeroFeeMarket = new NFTMarket(address(bit), 0, feeRecipient);

        // 给 seller 再铸造一枚 NFT
        vm.prank(owner);
        nft.safeMint(seller, "2.json");

        uint256 price = 1000 ether;

        // seller 上架
        vm.startPrank(seller);
        nft.approve(address(zeroFeeMarket), 2);
        zeroFeeMarket.list(nft, 2, price);
        vm.stopPrank();

        uint256 sellerBalBefore = bit.balanceOf(seller);

        // buyer 购买
        vm.startPrank(buyer);
        bit.approve(address(zeroFeeMarket), price);
        zeroFeeMarket.buy(nft, 2);
        vm.stopPrank();

        // 卖家获得全部金额
        assertEq(bit.balanceOf(seller), sellerBalBefore + price);
        assertEq(nft.ownerOf(2), buyer);
    }

    // =============================================================
    // Fuzz tests
    // =============================================================

    function testFuzz_Buy_PaymentCorrect(
        uint256 price,
        uint256 feeBps
    ) public {
        price = bound(price, 1 ether, 10000 ether);
        feeBps = bound(feeBps, 0, 1000); // 0% - 10%

        // 部署临时市场合约
        vm.prank(owner);
        NFTMarket fuzzMarket = new NFTMarket(address(bit), feeBps, feeRecipient);

        // mint NFT 给 seller
        uint256 tokenId;
        vm.prank(owner);
        tokenId = nft.safeMint(seller, "fuzz.json");

        // seller 上架
        vm.startPrank(seller);
        nft.approve(address(fuzzMarket), tokenId);
        fuzzMarket.list(nft, tokenId, price);
        vm.stopPrank();

        uint256 sellerBalBefore = bit.balanceOf(seller);
        uint256 feeRecipientBalBefore = bit.balanceOf(feeRecipient);

        // buyer 购买
        vm.startPrank(buyer);
        bit.approve(address(fuzzMarket), price);
        fuzzMarket.buy(nft, tokenId);
        vm.stopPrank();

        uint256 expectedFee = (price * feeBps) / 10000;
        uint256 expectedSellerProceeds = price - expectedFee;

        assertEq(bit.balanceOf(seller), sellerBalBefore + expectedSellerProceeds);
        assertEq(bit.balanceOf(feeRecipient), feeRecipientBalBefore + expectedFee);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function testFuzz_Cancel_ReturnsNFT(uint256 price) public {
        price = bound(price, 1 ether, 10000 ether);

        vm.prank(owner);
        uint256 tokenId = nft.safeMint(seller, "cancel-fuzz.json");

        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(nft, tokenId, price);
        vm.stopPrank();

        // 取消
        vm.prank(seller);
        market.cancel(nft, tokenId);

        assertEq(nft.ownerOf(tokenId), seller);
    }
}
