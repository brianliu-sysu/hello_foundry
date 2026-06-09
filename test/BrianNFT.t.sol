// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianNFT} from "../src/nft/BrianNFT.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract BrianNFTTest is Test {
    BrianNFT public nft;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");

    string constant BASE_URI = "https://metadata.example.com/token/";

    function setUp() public {
        vm.prank(owner);
        nft = new BrianNFT("BrianNFT", "BNFT", BASE_URI, 100);
    }

    // =============================================================
    // 部署
    // =============================================================

    function test_Deploy_NameAndSymbol() public view {
        assertEq(nft.name(), "BrianNFT");
        assertEq(nft.symbol(), "BNFT");
    }

    function test_Deploy_OwnerSet() public view {
        assertEq(nft.owner(), owner);
    }

    function test_Deploy_MaxSupplyAndBaseURI() public view {
        assertEq(nft.maxSupply(), 100);
        // baseURI 未暴露为 public，但可通过 tokenURI 间接验证
    }

    function test_Deploy_NextTokenIdStartsAt1() public view {
        assertEq(nft.nextTokenId(), 1);
    }

    function test_Deploy_SupportsInterfaces() public view {
        // IERC721Enumerable 定义了外部函数，因此可以通过 type().interfaceId 获取
        assertTrue(nft.supportsInterface(type(IERC721Enumerable).interfaceId));
        // IERC4906 仅定义了事件，interface ID 为常量 0x49064906
        assertTrue(nft.supportsInterface(0x49064906));
    }

    // =============================================================
    // safeMint（owner only）
    // =============================================================

    function test_SafeMint_MintsToRecipient() public {
        vm.prank(owner);
        uint256 tokenId = nft.safeMint(alice, "1.json");

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_SafeMint_IncrementsTokenId() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "1.json");
        nft.safeMint(bob, "2.json");
        vm.stopPrank();

        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.totalMinted(), 2);
        assertEq(nft.nextTokenId(), 3);
    }

    function test_SafeMint_SetsTokenURI() public {
        vm.prank(owner);
        nft.safeMint(alice, "1.json");

        string memory uri = nft.tokenURI(1);
        assertEq(uri, string.concat(BASE_URI, "1.json"));
    }

    function test_SafeMint_EmitsMintedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit BrianNFT.Minted(alice, 1, "1.json");

        vm.prank(owner);
        nft.safeMint(alice, "1.json");
    }

    function test_SafeMint_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.safeMint(alice, "1.json");
    }

    function test_SafeMint_RevertsWhenMaxSupplyReached() public {
        vm.startPrank(owner);
        for (uint256 i = 0; i < 100; i++) {
            nft.safeMint(alice, "");
        }
        vm.stopPrank();

        assertEq(nft.totalMinted(), 100);

        vm.prank(owner);
        vm.expectRevert("BrianNFT: max supply reached");
        nft.safeMint(alice, "");
    }

    // =============================================================
    // safeMintBatch
    // =============================================================

    function test_SafeMintBatch_MintsAll() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = owner;

        string[] memory uris = new string[](3);
        uris[0] = "a.json";
        uris[1] = "b.json";
        uris[2] = "c.json";

        vm.prank(owner);
        nft.safeMintBatch(recipients, uris);

        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.ownerOf(3), owner);
        assertEq(nft.totalMinted(), 3);
    }

    function test_SafeMintBatch_RevertsWhenLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        string[] memory uris = new string[](1);
        uris[0] = "a.json";

        vm.prank(owner);
        vm.expectRevert("BrianNFT: length mismatch");
        nft.safeMintBatch(recipients, uris);
    }

    function test_SafeMintBatch_RevertsWhenNotOwner() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        string[] memory uris = new string[](1);
        uris[0] = "a.json";

        vm.prank(alice);
        vm.expectRevert();
        nft.safeMintBatch(recipients, uris);
    }

    // =============================================================
    // 枚举（ERC721Enumerable）
    // =============================================================

    function test_Enumerable_TotalSupply() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "1.json");
        nft.safeMint(bob, "2.json");
        nft.safeMint(alice, "3.json");
        vm.stopPrank();

        assertEq(nft.totalSupply(), 3);
    }

    function test_Enumerable_TokenOfOwnerByIndex() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "a.json");
        nft.safeMint(alice, "b.json");
        nft.safeMint(bob, "c.json");
        vm.stopPrank();

        assertEq(nft.tokenOfOwnerByIndex(alice, 0), 1);
        assertEq(nft.tokenOfOwnerByIndex(alice, 1), 2);
        assertEq(nft.tokenOfOwnerByIndex(bob, 0), 3);
    }

    function test_Enumerable_TokenByIndex() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "1.json");
        nft.safeMint(bob, "2.json");
        vm.stopPrank();

        assertEq(nft.tokenByIndex(0), 1);
        assertEq(nft.tokenByIndex(1), 2);
    }

    function test_Enumerable_RevertsOnOutOfBounds() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "1.json");
        vm.stopPrank();

        vm.expectRevert();
        nft.tokenOfOwnerByIndex(alice, 1);
    }

    // =============================================================
    // Owner 管理
    // =============================================================

    function test_SetBaseURI_UpdatesTokenURI() public {
        vm.prank(owner);
        nft.safeMint(alice, "1.json");

        vm.prank(owner);
        nft.setBaseURI("https://new.example.com/");

        assertEq(nft.tokenURI(1), "https://new.example.com/1.json");
    }

    function test_SetBaseURI_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit BrianNFT.BaseURIUpdated("https://new.example.com/");

        vm.prank(owner);
        nft.setBaseURI("https://new.example.com/");
    }

    function test_SetBaseURI_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.setBaseURI("https://evil.example.com/");
    }

    function test_SetMaxSupply_Increases() public {
        vm.prank(owner);
        nft.setMaxSupply(200);
        assertEq(nft.maxSupply(), 200);
    }

    function test_SetMaxSupply_Unlimited() public {
        vm.prank(owner);
        nft.setMaxSupply(0);
        assertEq(nft.maxSupply(), 0);
    }

    function test_SetMaxSupply_RevertsBelowMinted() public {
        vm.startPrank(owner);
        nft.safeMint(alice, "1.json");
        nft.safeMint(alice, "2.json");
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert("BrianNFT: below minted");
        nft.setMaxSupply(1);
    }

    function test_SetMaxSupply_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.setMaxSupply(999);
    }

    // =============================================================
    // 无上限供应
    // =============================================================

    function test_UnlimitedSupply() public {
        vm.prank(owner);
        BrianNFT unlimited = new BrianNFT("U", "U", "", 0);

        assertEq(unlimited.maxSupply(), 0);

        vm.startPrank(owner);
        for (uint256 i = 0; i < 200; i++) {
            unlimited.safeMint(alice, "");
        }
        vm.stopPrank();

        assertEq(unlimited.totalSupply(), 200);
    }

    // =============================================================
    // Fuzz test
    // =============================================================

    function testFuzz_SafeMint_OwnerOfMatches(
        uint256 amount
    ) public {
        amount = bound(amount, 1, 100);

        vm.startPrank(owner);
        for (uint256 i = 0; i < amount; i++) {
            nft.safeMint(alice, "");
        }
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), amount);
        assertEq(nft.totalSupply(), amount);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(amount), alice);
    }
}
