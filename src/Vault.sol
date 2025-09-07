//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IRebaseToken } from "./interfaces/IRebaseToken.sol";


contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH the user has sent
    // create a redeem function that burns tokens from the user and sends ETH to the user
    // create a way to add rewards to the vaut

    
    //***************   ERRORS   ***************
    error Vault__RedeemFailed(uint256 amount);

    
    //***************   STATE VARIABLES   ***************
    IRebaseToken private immutable i_rebaseToken;

    
    
    //***************   EVENTS   ***************
    event Vault__Deposited(address indexed user, uint256 amount);
    event Vault__Redeemed(address indexed user, uint256 amount);
    
    
    //***************   CONSTRUCTOR   ***************
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }


    //***************   RECEIVE   ***************
    receive() external payable {}


    //***************   EXTERNAL   ***************

    /**
     * @dev Allows users to deposit ETH and receive vault tokens.
     */
    function deposit() external payable {
        // 1. we need to use the amount of ETH the user has sent to mint tokens to the vault
        require(msg.value > 0, "Must send ETH to deposit");
        // mint tokens to the user
        uint256 userInterestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, userInterestRate);
        emit Vault__Deposited(msg.sender, msg.value);
    }

    /**
     * @dev Allows users to redeem vault tokens for ETH.
     */
    // aderyn-ignore-next-line(eth-send-unchecked-address)
    function redeem(uint256 _amount) external {
        require(_amount > 0, "Must have tokens to redeem");

        // Get user balance first for proper validation
        uint256 userBalance = i_rebaseToken.balanceOf(msg.sender);
        require(userBalance >= _amount, "Insufficient token balance");

        if (_amount == type(uint256).max) {
            _amount = userBalance;
        }
        
        // burn tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // send ETH to the user
        (bool success, )= payable(msg.sender).call{ value: _amount }("");
        if (!success) {
            revert Vault__RedeemFailed(_amount);
        }
        emit Vault__Redeemed(msg.sender, _amount);
    }


    //***************   VIEW / PURE   ***************

    /**
     * @dev Returns the address of the rebase token.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}