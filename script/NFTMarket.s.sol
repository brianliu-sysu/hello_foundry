// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {BrianNFT} from "../src/nft/BrianNFT.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {NFTMarket} from "../src/nft/NFTMarket.sol";

/// @notice 一键部署 BrianNFT、BrianICOToken 和 NFTMarket
contract NFTMarketScript is BaseScript {
    BrianNFT public brianNft;
    BrianICOToken public brianICOToken;
    NFTMarket public nftMarket;

    function run() public {
        broadcast();

        // 1. 部署 BrianNFT（maxSupply = 0 表示无上限）
        brianNft = new BrianNFT(
            "BrianNFT",
            "BNFT",
            "ipfs://",   // baseTokenURI
            0             // maxSupply（0 = 无上限）
        );
        brianNft.safeMint(deployer, "bafybeib233ynka3n4xdtxawesq5rvvu2dtzlvhk4ca6ywhcgfx4fkj63ni");
        saveDeployment("BrianNFT", address(brianNft));

        // 2. 部署 BrianICOToken（初始供应 100 万 BIT）
        brianICOToken = new BrianICOToken(1_000_000 ether);
        saveDeployment("BrianICOToken", address(brianICOToken));

        // 3. 部署 NFTMarket（手续费 2.5%，手续费接收方为部署者）
        nftMarket = new NFTMarket(
            address(brianICOToken),
            250,           // feeBps = 2.5%
            deployer       // 手续费接收方
        );
        saveDeployment("NFTMarket", address(nftMarket));

        vm.stopBroadcast();
    }
}
