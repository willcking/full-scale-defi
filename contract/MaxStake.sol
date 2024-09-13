// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./interface/IERC20.sol";
import "./token/ERC20.sol";
import "./interface/IMaxStake.sol";
import "./utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MaxStake is IMaxStake,ReentrancyGuard,Initializable,UUPSUpgradeable,AccessControlUpgradeable,PausableUpgradeable {
    IERC20 public rewardtoken;
    IERC20 public interestToken;

    uint256 public initInterest;
    uint256 public startTimeStamp;
    uint256 public endTimeStamp;
    uint256 public rewardPerSecond;
    uint256 public totalAllocPoint;
    uint256 public totalRewards;
    uint256 public paidout;
    address public _owner;
    Pool[] public pools;    
    // User deposits in the liquidity pool
    mapping(uint256 => mapping(address => User)) userInfo;
    
}