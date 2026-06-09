pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-3.0

contract CalledContract {
    event callEvent(address sender, address origin, address from);

    function calledFunction() public returns (address sender, address origin, address from) {
        sender = msg.sender;
        origin = tx.origin;
        from = address(this);
        emit callEvent(sender, origin, from);
        return (sender, origin, from);
    }
}

library CalledLibrary {
    function calledFunction() public view returns (address sender, address origin, address from) {
        return (msg.sender, tx.origin, address(this));
    }
}

contract Caller {
    function makeCalls(CalledContract _calledContract) public {
        (address sender, address origin, address from) = _calledContract.calledFunction();
        (bool res,) = address(_calledContract).call(abi.encodeWithSignature("calledFunction()"));
        require(res, "call failed");
        (res,) = address(_calledContract).delegatecall(abi.encodeWithSignature("calledFunction()"));
        require(res, "delegatecall failed");
        (sender, origin, from) = CalledLibrary.calledFunction();
    }
}
