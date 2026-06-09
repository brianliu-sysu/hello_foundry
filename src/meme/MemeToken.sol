// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @notice MemeToken — ERC20 模板，供 MemeFactory 最小代理克隆使用。
/// @dev    模板本身通过 Initializable 锁死，不可直接使用。
///         每个 clone 必须调用一次 initialize() 设置自己的 name/symbol/supply。
contract MemeToken is ERC20, Ownable, Initializable {
    // 每个 clone 独立存储的真实名称和符号
    string private _memeName;
    string private _memeSymbol;

    /// @dev 模板构造：塞空字符串给 ERC20，并锁死初始化器。
    constructor() ERC20("", "") Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice 初始化 clone（仅可调用一次）
    /// @param name_       代币名称
    /// @param symbol_     代币符号
    /// @param totalSupply_ 初始供应量（全部 mint 给 owner_）
    /// @param owner_       代币持有者及 owner
    function initialize(string calldata name_, string calldata symbol_, uint256 totalSupply_, address owner_)
        external
        initializer
    {
        require(totalSupply_ > 0, "MemeToken: supply must be > 0");
        require(owner_ != address(0), "MemeToken: owner cannot be zero");

        _memeName = name_;
        _memeSymbol = symbol_;
        _transferOwnership(owner_);
        _mint(owner_, totalSupply_);
    }

    /// @notice 重写 name()，返回 clone 自己的值
    function name() public view override returns (string memory) {
        return _memeName;
    }

    /// @notice 重写 symbol()，返回 clone 自己的值
    function symbol() public view override returns (string memory) {
        return _memeSymbol;
    }
}
