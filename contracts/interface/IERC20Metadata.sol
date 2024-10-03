// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Strings.sol)

pragma solidity ^0.8.20;

/**
 * @dev String operations.
 */
interface IERC20Metadata {

    /**
    *  @dev return token name
     */
    function name() external view returns (string memory);

    /**
     * @dev return token symbol
     */
    function symbol() external view returns (string memory);

    /**
    * @dev return decimals
     */
    function decimals() external view returns (uint8);
    
}