// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

/// @notice Minimal Permit2 SignatureTransfer interface
/// @dev  Permit2 singleton: 0x000000000022D473030F116dDEE9F6B43aC78BA3 (all EVM chains)
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}
