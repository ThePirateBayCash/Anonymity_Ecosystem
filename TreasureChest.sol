// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract TreasureChest {
    address public immutable owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function withdraw(address token, address recipient) external {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        require(IERC20(token).balanceOf(address(this)) > 0, "Error: No treasure found in chest");
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }
}
