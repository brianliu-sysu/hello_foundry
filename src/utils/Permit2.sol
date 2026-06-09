// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";

/// @notice Permit2 — Uniswap-style SignatureTransfer
/// @dev  Deploy to 0x000000000022D473030F116dDEE9F6B43aC78BA3 (canonical address).
///       Implements the Permit2 SignatureTransfer flow: users sign an off-chain
///       EIP-712 message authorizing a token+amount; anyone submits it on-chain
///       to transfer tokens from the signer.
contract Permit2 is ISignatureTransfer {
    /// @notice Canonical Permit2 address (same on all EVM chains)
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Tracks used nonces per user (true = used)
    mapping(address user => mapping(uint256 nonce => bool used)) public nonceUsed;

    /// @notice Contract owner (can recover stuck tokens)
    address public immutable owner;

    // EIP-712 typehash: PermitTransferFrom(TokenPermissions permitted,uint256 nonce,uint256 deadline)
    //                    TokenPermissions(address token,uint256 amount)
    bytes32 private constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    bytes32 private constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    modifier onlyOwner() {
        require(msg.sender == owner, "Permit2: only owner");
        _;
    }

    constructor(address owner_) {
        owner = owner_;
    }

    /// @notice Compute EIP-712 domain separator dynamically.
    /// @dev    Non-immutable so that vm.etch to canonical address works correctly.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(_EIP712_DOMAIN_TYPEHASH, keccak256("Permit2"), block.chainid, address(this)));
    }

    // ================================================================
    // ISignatureTransfer
    // ================================================================

    /// @notice Execute a Permit2 SignatureTransfer
    /// @dev    The signer must have previously approved this contract as an ERC20 spender.
    ///         Signature format: 65 bytes (r || s || v).
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner_,
        bytes calldata signature
    ) external override {
        require(block.timestamp <= permit.deadline, "Permit2: deadline expired");
        require(!nonceUsed[owner_][permit.nonce], "Permit2: nonce already used");

        // Verify EIP-712 signature
        bytes32 domainSeparator = DOMAIN_SEPARATOR();

        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount));

        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissionsHash, permit.nonce, permit.deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover from 65-byte signature: r (32) || s (32) || v (1)
        address recovered = ecrecover(digest, uint8(signature[64]), bytes32(signature[0:32]), bytes32(signature[32:64]));
        require(recovered == owner_ && recovered != address(0), "Permit2: invalid signature");

        nonceUsed[owner_][permit.nonce] = true;

        // Execute transfer — Permit2 must have ERC20 allowance from owner
        require(
            IERC20(permit.permitted.token).transferFrom(owner_, transferDetails.to, transferDetails.requestedAmount),
            "Permit2: transferFrom failed"
        );
    }

    // ================================================================
    // Admin
    // ================================================================

    /// @notice Recover ERC20 tokens accidentally sent to this contract
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(to, amount), "Permit2: rescue transfer failed");
    }
}
