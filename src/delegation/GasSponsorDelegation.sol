// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title GasSponsorDelegation
/// @notice EIP-7702 delegation contract — after an EOA signs a 7702 authorization
///         pointing to this contract, anyone (a relayer) can call the EOA's
///         `claimETH` / `claimToken` functions. The delegation code calls into
///         the Faucet, which sees msg.sender == the EOA — so cooldown tracking
///         works naturally. The relayer receives a configurable fee from the
///         claimed amount as gas compensation.

interface IFaucet {
    function withdraw(uint256 _withdrawAmount, address payable _to) external;
    function withdrawToken(uint256 amount) external;
    function token() external view returns (address);
}

contract GasSponsorDelegation {
    /// @notice Maximum fee the user allows the relayer to take (basis points, e.g. 100 = 1%)
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    /// @notice ETH claim limit per call (matches Faucet MAX_WITHDRAW / 0.01 ether)
    uint256 public constant ETH_CLAIM_LIMIT = 0.01 ether;

    /// @notice Token claim limit per call (matches Faucet MAX_TOKEN_WITHDRAW / 10 tokens)
    uint256 public constant TOKEN_CLAIM_LIMIT = 10 ether;

    /// @dev Emitted when a relayer successfully claims ETH on behalf of a user
    event ETHClaimed(address indexed user, uint256 amount, address indexed relayer, uint256 fee);

    /// @dev Emitted when a relayer successfully claims tokens on behalf of a user
    event TokenClaimed(address indexed user, uint256 amount, address indexed relayer, uint256 fee);

    /// @notice Claim ETH from a Faucet. The ETH goes to the user's EOA (address(this)
    ///         in delegation context), minus a fee paid to the relayer.
    /// @param faucet    Faucet contract address
    /// @param relayer   Address to receive the gas-compensation fee
    /// @param feeBps    Fee in basis points (must be <= MAX_FEE_BPS)
    function claimETH(address faucet, address relayer, uint256 feeBps) external {
        require(feeBps <= MAX_FEE_BPS, "fee too high");
        require(relayer != address(0), "relayer is zero");

        uint256 balanceBefore = address(this).balance;

        // In EIP-7702 delegation context, msg.sender in the downstream Faucet
        // call is the EOA itself — so cooldown is naturally enforced per-user.
        IFaucet(faucet).withdraw(ETH_CLAIM_LIMIT, payable(address(this)));

        uint256 received = address(this).balance - balanceBefore;
        require(received > 0, "nothing claimed");

        uint256 fee = (received * feeBps) / 10000;
        if (fee > 0) {
            (bool okFee,) = relayer.call{value: fee}("");
            require(okFee, "fee transfer failed");
        }

        emit ETHClaimed(address(this), received, relayer, fee);
    }

    /// @notice Claim tokens from a Faucet. Tokens go to the user's EOA,
    ///         minus a fee paid to the relayer.
    /// @param faucet    Faucet contract address
    /// @param relayer   Address to receive the gas-compensation fee
    /// @param feeBps    Fee in basis points (must be <= MAX_FEE_BPS)
    function claimToken(address faucet, address relayer, uint256 feeBps) external {
        require(feeBps <= MAX_FEE_BPS, "fee too high");
        require(relayer != address(0), "relayer is zero");

        IFaucet faucetContract = IFaucet(faucet);
        address tokenAddr = faucetContract.token();
        require(tokenAddr != address(0), "faucet token not set");

        // Record token balance before the claim (using staticcall via the token interface)
        uint256 balanceBefore = _tokenBalance(tokenAddr);

        // Faucet sees msg.sender == EOA, cooldown enforced naturally.
        // Token claim limit: 10 tokens (18 decimals).
        faucetContract.withdrawToken(TOKEN_CLAIM_LIMIT);

        uint256 received = _tokenBalance(tokenAddr) - balanceBefore;
        require(received > 0, "nothing claimed");

        uint256 fee = (received * feeBps) / 10000;
        if (fee > 0) {
            (bool okFee,) = tokenAddr.call(
                abi.encodeWithSignature("transfer(address,uint256)", relayer, fee)
            );
            require(okFee, "fee transfer failed");
        }

        emit TokenClaimed(address(this), received, relayer, fee);
    }

    /// @notice Fallback — accept ETH (so the EOA can receive ETH while delegated)
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════════
    // Internal helpers
    // ═══════════════════════════════════════════════════════════════

    function _tokenBalance(address tokenAddr) internal view returns (uint256 bal) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000) // balanceOf(address)
            mstore(add(ptr, 4), address())
            let ok := staticcall(gas(), tokenAddr, ptr, 36, ptr, 32)
            if ok { bal := mload(ptr) }
        }
    }
}
