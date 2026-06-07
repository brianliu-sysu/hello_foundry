pragma solidity ^0.8.13;

/// @title Proxy
/// @notice Minimal EIP-1967 upgradeable proxy — delegates all calls to an
///         implementation contract via delegatecall. Uses unstructured storage
///         (EIP-1967 slots) to avoid storage collisions with the implementation.
contract Proxy {
    /// @dev EIP-1967 storage slots: keccak256(…) - 1, so they don't collide
    ///      with the storage layout of any sensible implementation contract.
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant OWNER_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event Upgraded(address indexed implementation);

    modifier onlyOwner() {
        require(msg.sender == _getOwner(), "Proxy: not owner");
        _;
    }

    constructor(address implementation_) {
        _setOwner(msg.sender);
        _setImplementation(implementation_);
    }

    /// @notice Upgrade the implementation contract address
    /// @param implementation_ New implementation address
    function upgrade(address implementation_) external onlyOwner {
        _setImplementation(implementation_);
        emit Upgraded(implementation_);
    }

    /// @notice Fallback — delegatecall to the implementation contract
    fallback() external payable {
        address impl = _getImplementation();
        require(impl != address(0), "Proxy: implementation not set");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Accept ETH transfers
    receive() external payable {}

    // ─── Internal helpers ───────────────────────────────────────────

    function _getImplementation() internal view returns (address impl) {
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }
    }

    function _setImplementation(address impl) internal {
        assembly {
            sstore(IMPLEMENTATION_SLOT, impl)
        }
    }

    function _getOwner() internal view returns (address owner) {
        assembly {
            owner := sload(OWNER_SLOT)
        }
    }

    function _setOwner(address owner) internal {
        assembly {
            sstore(OWNER_SLOT, owner)
        }
    }
}