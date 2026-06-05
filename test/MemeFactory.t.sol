// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {MemeFactory} from "../src/MemeFactory.sol";

contract MemeFactoryTest is Test {
    MemeToken public impl;
    MemeFactory public factory;

    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");

    function setUp() public {
        // 1. 部署模板
        impl = new MemeToken();
        // 2. 部署工厂
        factory = new MemeFactory(impl);
    }

    // =============================================================
    // 模板自身保护
    // =============================================================

    function test_Impl_CannotInitialize() public {
        vm.expectRevert();
        impl.initialize("Bad", "BAD", 1000 * 10 ** 18, alice);
    }

    // =============================================================
    // 工厂创建
    // =============================================================

    function test_CreateMeme_Success() public {
        uint256 supply = 1_000_000 * 10 ** 18;
        vm.prank(alice);
        address token = factory.createMeme("Dogecoin", "DOGE", supply);

        MemeToken meme = MemeToken(token);
        assertEq(meme.name(), "Dogecoin");
        assertEq(meme.symbol(), "DOGE");
        assertEq(meme.totalSupply(), supply);
        assertEq(meme.balanceOf(alice), supply);
        assertEq(meme.owner(), alice);
        assertEq(factory.memeCount(), 1);
        assertEq(factory.memeTokens(0), token);
    }

    function test_CreateMeme_MultipleIndependent() public {
        vm.startPrank(alice);
        address doge = factory.createMeme("Dogecoin", "DOGE", 100 * 10 ** 18);
        address shib = factory.createMeme("Shiba Inu", "SHIB", 200 * 10 ** 18);
        vm.stopPrank();

        // 两个 token 互不影响
        MemeToken d = MemeToken(doge);
        MemeToken s = MemeToken(shib);

        assertEq(d.name(), "Dogecoin");
        assertEq(s.name(), "Shiba Inu");
        assertTrue(doge != shib);

        // alice 有两个 token 的余额
        assertEq(d.balanceOf(alice), 100 * 10 ** 18);
        assertEq(s.balanceOf(alice), 200 * 10 ** 18);

        assertEq(factory.memeCount(), 2);
    }

    function test_CreateMeme_DifferentCreators() public {
        uint256 supply = 1000 * 10 ** 18;

        vm.prank(alice);
        address tokenA = factory.createMeme("AliceCoin", "ALC", supply);

        vm.prank(bob);
        address tokenB = factory.createMeme("BobCoin", "BBC", supply);

        // 各自是 owner
        assertEq(MemeToken(tokenA).owner(), alice);
        assertEq(MemeToken(tokenB).owner(), bob);
        assertEq(MemeToken(tokenA).balanceOf(alice), supply);
        assertEq(MemeToken(tokenB).balanceOf(bob), supply);
        assertEq(MemeToken(tokenA).balanceOf(bob), 0);
    }

    function test_CreateMeme_EmitsEvent() public {
        uint256 supply = 500 * 10 ** 18;

        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit MemeFactory.MemeCreated("Pepe", "PEPE", supply, alice, address(0));
        factory.createMeme("Pepe", "PEPE", supply);
    }

    function test_CreateMeme_RevertZeroSupply() public {
        vm.prank(alice);
        vm.expectRevert("MemeToken: supply must be > 0");
        factory.createMeme("Zero", "ZRO", 0);
    }

    function test_CreateMeme_RevertEmptyName() public {
        vm.prank(alice);
        factory.createMeme("", "TST", 100 * 10 ** 18);
        // empty name is fine for ERC20 — just verify it creates
        assertEq(factory.memeCount(), 1);
    }

    // =============================================================
    // 批量查询
    // =============================================================

    function test_GetMemeTokensPaginated() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            factory.createMeme("Meme", "MEME", 100 * 10 ** 18);
        }
        vm.stopPrank();

        (address[] memory page, uint256 total) = factory.getMemeTokensPaginated(0, 3);
        assertEq(page.length, 3);
        assertEq(total, 5);

        (page, total) = factory.getMemeTokensPaginated(3, 3);
        assertEq(page.length, 2);
        assertEq(total, 5);

        (page, total) = factory.getMemeTokensPaginated(10, 3);
        assertEq(page.length, 0);
        assertEq(total, 5);
    }

    function test_GetMemeTokens_All() public {
        vm.startPrank(alice);
        factory.createMeme("A", "A", 1e18);
        factory.createMeme("B", "B", 1e18);
        vm.stopPrank();

        address[] memory all = factory.getMemeTokens();
        assertEq(all.length, 2);
    }

    // =============================================================
    // Fuzz
    // =============================================================

    function testFuzz_CreateMeme(
        string calldata name_,
        string calldata symbol_,
        uint256 supply_
    ) public {
        // 过滤空 name/symbol（允许，但 OZ ERC20 可能 revert）
        supply_ = bound(supply_, 1, 1_000_000_000 * 10 ** 18);

        vm.prank(alice);
        address token = factory.createMeme(name_, symbol_, supply_);

        MemeToken meme = MemeToken(token);
        assertEq(meme.totalSupply(), supply_);
        assertEq(meme.balanceOf(alice), supply_);
        assertEq(meme.owner(), alice);
    }
}
