// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title BatchTransferDelegation
/// @notice EIP-7702 delegation contract — after an EOA signs a 7702 authorization
///         pointing to this contract, the EOA can execute batch transfers (ERC20 + ETH)
///         atomically in a single transaction. No separate approve needed.
///
///         Since this contract's code runs in the EOA's own context (EIP-7702),
///         `msg.sender` in downstream calls is the EOA itself — so `token.transfer()`
///         works directly (the EOA is the token owner).
contract BatchTransferDelegation {
    /// @dev Emitted after a successful batch ERC20 transfer
    /// @param from     The EOA that executed the batch (address(this) in delegation context)
    /// @param count    Number of transfers in the batch
    event BatchTransferExecuted(address indexed from, uint256 count);

    /// @dev Emitted after a successful batch ETH transfer
    /// @param from     The EOA that executed the batch
    /// @param count    Number of recipients
    event BatchTransferETHExecuted(address indexed from, uint256 count);

    /// @dev Emitted after a successful batch call
    /// @param from     The EOA that executed the batch
    /// @param count    Number of calls in the batch
    event BatchCallExecuted(address indexed from, uint256 count);

    /// @notice Batch transfer ERC20 tokens from this EOA to multiple recipients
    /// @dev    Each transfer is independent — if one fails, others still execute.
    ///         Returns a bool[] so callers can check individual results.
    /// @param  tokens     Array of ERC20 token contract addresses
    /// @param  recipients Array of recipient addresses
    /// @param  amounts    Array of amounts (in token decimals)
    /// @return results    bool[] — true for each successful transfer
    function batchTransfer(address[] calldata tokens, address[] calldata recipients, uint256[] calldata amounts)
        external
        returns (bool[] memory results)
    {
        uint256 len = tokens.length;
        require(len == recipients.length && len == amounts.length, "BatchTransfer: length mismatch");

        results = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            // Regular CALL — in EIP-7702 delegation context, the EOA is the caller,
            // so token.transfer() works directly (EOA owns the tokens).
            (bool ok,) = tokens[i].call(abi.encodeWithSignature("transfer(address,uint256)", recipients[i], amounts[i]));
            results[i] = ok;
        }

        emit BatchTransferExecuted(address(this), len);
    }

    /// @notice Batch transfer ETH from this EOA to multiple recipients
    /// @dev    Each transfer is independent — if one fails, others still execute.
    ///         ETH comes from the EOA's balance (the delegation code runs in the EOA's context).
    /// @param  recipients Array of recipient addresses
    /// @param  amounts    Array of amounts (in wei)
    /// @return results    bool[] — true for each successful transfer
    function batchTransferETH(address[] calldata recipients, uint256[] calldata amounts)
        external
        returns (bool[] memory results)
    {
        uint256 len = recipients.length;
        require(len == amounts.length, "BatchTransfer: length mismatch");

        results = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            (bool ok,) = recipients[i].call{value: amounts[i]}("");
            results[i] = ok;
        }

        emit BatchTransferETHExecuted(address(this), len);
    }

    /// @notice Execute arbitrary batch calls from this EOA
    /// @dev    Each call is independent — if one fails, others still execute.
    ///         Since this runs in EIP-7702 delegation context, msg.sender
    ///         in downstream calls is the EOA itself.
    ///         Supports ETH transfer by setting msg.value in the values array.
    /// @param  targets  Array of target contract addresses
    /// @param  values   Array of ETH values (in wei) to send with each call
    /// @param  payloads Array of calldata for each call
    /// @return results  bool[] — true for each successful call
    function batchCall(address[] calldata targets, uint256[] calldata values, bytes[] calldata payloads)
        external
        returns (bool[] memory results)
    {
        uint256 len = targets.length;
        require(len == values.length && len == payloads.length, "BatchCall: length mismatch");

        results = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            (bool ok,) = targets[i].call{value: values[i]}(payloads[i]);
            results[i] = ok;
        }

        emit BatchCallExecuted(address(this), len);
    }

    /// @notice Fallback — accept ETH (so the EOA can receive ETH while delegated)
    receive() external payable {}
}
