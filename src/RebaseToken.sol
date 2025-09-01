//SPDX-License-Identifier: MIT

/**Layots of contract
* version
* imports
* interfaces, libraries, contracts
* errors
* type declarations
* state variables
* events
* modifiers
* functions
 */

/**Layout of functions:
* constructor
* receive functions (if exist)
* fallback functions (if exist)
* external
* public
* internal
* private
* view / pure
*/

pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/access/AccessControl.sol";

/*
* @title RebaseToken
* @note A token that can rebase its supply
* @note The interest rate in the smart contract can only decrease 
* @note Each user will have their own interest rate that is global interest rate at the time of deposit
*/


contract RebaseToken is ERC20, Ownable, AccessControl {

    //errors
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 currentInterestRate);

    // state variables
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = 5e10; // interest rate per second 

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // events
    event RebaseToken__InterestRateUpdated(uint256 newInterestRate);


    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    
    //***************   EXTERNAL   ***************
    /**
        * @dev Sets a new interest rate for the token.
        * @param _newInterestRate The new interest rate to be set.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Logic to set the new interest rate
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(_newInterestRate, s_interestRate);
        }
        s_interestRate = _newInterestRate;
        emit RebaseToken__InterestRateUpdated(_newInterestRate);
    }

    /**
     * @dev Grants the mint and burn role to a specified account.
     * @param _account The address to grant the role to.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
        * @notice Mint the user tokens when they deposit to the vault
        * @dev Mints new tokens to the specified address.
        * @param _to The address to mint tokens to.
        * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = s_interestRate; // we set new interest rate except bridging
        _mint(_to, _amount);
    }


    /**
        * @notice Burn the user tokens when they withdraw from the vault
        * @dev Burns tokens from the specified address.
        * @param _from The address to burn tokens from.
        * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }


    //***************   PUBLIC   ***************
    /**
        * @notice Transfer tokens from one address to another.
        * @dev Overrides the transfer function to include interest minting.
        * @param _to The address to transfer tokens to.
        * @param _amount The amount of tokens to transfer.
        * @return A boolean indicating the success of the transfer.
     */
    function transfer(address _to, uint256 _amount) public override returns (bool){
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_to, _amount);
    }


    /**
        * @notice Transfer tokens from one address to another.
        * @dev Overrides the transfer function to include interest minting.
        * @param _from The address to transfer tokens from.
        * @param _to The address to transfer tokens to.
        * @param _amount The amount of tokens to transfer.
        * @return A boolean indicating the success of the transfer.
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRates[_to] = s_userInterestRates[_from];
        }
        return super.transferFrom(_from, _to, _amount);
    }


    //***************   INTERNAL   ***************
    /**
        * @notice Mint any accrued interest for a user since the last time they interacted with protocol (e.g mint, burn, transfer)
        * @param _user The address of the user to mint interest for.
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of token that need to be minted to the user -> (2) - (1) -> interest
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint tokens to the user
        _mint(_user, balanceIncrease);

        // uint256 userInterestRate = s_userInterestRates[_user];
        // if (userInterestRate == 0) {
        //     return;
        // }
        // uint256 interestDifference = s_interestRate - userInterestRate;
        // uint256 interest = (balanceOf(_user) * interestDifference) / 1e10;
        // if (interest > 0) {
        //     _mint(_user, interest);
        // }
    }


    //***************   VIEW / PURE   ***************
    /**
        * @dev Returns the current interest rate.
        * @return The current interest rate.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }


    /**
        * @dev Returns the current principal balance of a user. This is the number of tokens that have currently minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol
        * @param _user The address of the user to query.
        * @return The current principal balance of the user.
     */
    function getPrincipalBalance(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }


    /**
        * @dev Returns the current interest rate that is currently set for the contract. Any future depositors will receive this interest.
        * @return The current interest rate.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }


    /**
        * @notice calculate the user balance that that has accumulated in the time since the balance was updated -> principle balance + some interest that was accrued
        * @dev Returns the current balance of the specified user.
        * @param _user The address of the user to query.
        * @return The current balance of the user.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that were actually minted to the user)
        // multiply the principle balance by the user's interest rate that has accumulated in the time since the balance was updated
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }


    /**
        * @notice Calculates the accumulated interest for a user since their last update.
        * @param _user The address of the user to query.
        * @return The accumulated interest for the user.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // we need to calculate the interest that has accumulated since last update
        // this is going to be linear growth over time
        // 1. calculate the time since last update
        // 2. calculate the amount of linear growth
        // linear interest = (principle balance) + ((principle balance) * (interest rate) * (time elapsed)) ==
        // == principle balance(1 + (interest rate) * (time elapsed))

        // deposit: 10 tokens
        // rate: 0.5 tokens per second
        // time: 2 seconds
        // (10) + ((10) * (0.5) * (2)) = 10 + 10 = 20 tokens

        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = 1 * PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
    }
}