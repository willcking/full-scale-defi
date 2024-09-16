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
    IERC20 public rewardToken;
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
    
    function initialize(address _b2stAddress, uint256 _rewardPerSecond, uint256 _startTimeStamp, uint256 _endTimeStamp) external initializer {
        require(_startTimeStamp < _endTimeStamp, "Invalid time");
        require(_endTimeStamp > block.timestamp, "Invalid end time");
        rewardToken = IERC20(_b2stAddress);
        rewardPerSecond = _rewardPerSecond;
        startTimeStamp = _startTimeStamp;
        endTimeStamp = _endTimeStamp;
        _owner = msg.sender;

        __UUPSUpgradeable_init();
    }

    //Update liquidity pool data and call when liquidity changes.
    function updatePool(uint256 pid) internal {
        Pool storage pool = pools[pid];

        uint256 lastTime = blocks.timestamp < endTimeStamp ? block.timestamp : endTimeStamp;
        if(lastTime <= pool.lastRewardBlock) {
            return;
        }

        uint256 totalSupply = pool.stTokenAmount;
        if(totalSupply == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }

        uint256 effectTime = lastTime - pool.lastRewardBlock;
        uint256 accRewardPerST = pool.accRewardPerST;

        uint256 reward = rewardPerSecond * (pool.poolWeight) * (effectTime) / (totalAllocPoint);
        accRewardPerST = accRewardPerST + (reward * (1e36) / (totalSupply)); 

        pool.accRewardPerST = accRewardPerST;
        pool.lastRewardBlock = block.timestamp;

        emit UpdatePool(pid, pool.lastRewardBlock, reward);
    }

    function Stake(uint256 pid, uint256 amount) external {
        require(block.timestamp < endTimeStamp, "Staking has ended");
        Pool storage pool = pools[pid];
        require(amount >= pool.minDepositAmount, "Amount less than limit");

        User storage user = userInfo[pid][msg.sender];

        //Update data every time user stake
        updatePool(pid);

        //claim reward
        if(user.stAmount > 0) {
            uint256 reward = pending(pid, msg.sender);
            user.finishedAmount += reward;
            user.pendingAmount = 0;

            rewardToken.transfer(msg.sender, reward);
        } else {
            user.pendingAmount = user.stAmount * (pool.accRewardPerST) / (1e36) - user.finishedAmount; 
        }

        IERC20(pool.stTokenAddress).transferFrom(msg.sender, address(this), amount);

        user.stAmount += amount;
        pool.stTokenAmount += amount;

        emit Stake(pid, amount);
    }

    function Withdraw(uint256 pid, uint256 amount) external {
        require(amount > 0, "Invalid Amount");
        User storage user = userInfo[pid][msg.sender];
        require(amount <= user.stAmount, "The balance less than amount");

        Pool storage pool = pools[pid];

        updatePool(pid);
        
        uint256 reward = pending(pid, msg.sender);
        user.finishedAmount += reward;
        user.pendingAmount = 0;
        rewardToken.transfer(msg.sender, reward);

        pool.stTokenAmount -= amount;
        user.stAmount -= amount;

        IERC20(pool.stTokenAddress).transfer(msg.sender, amount);

        emit Withdraw(pid, amount);
    }

    function claimReward(uint256 pid) external {
        User storage user = userInfo[pid][msg.sender];
        
        uint256 reward = pending(pid, msg.sender);
        user.finishedAmount += reward;
        user.pendingAmount = 0;
        rewardToken.transfer(msg.sender, reward);

        emit Reward(pid);
    }

    function pending(uint256 pid, address user) internal view returns(uint256) {
        User storage user = userInfo[pid][user];
        Pool storage pool = pools[pid];

        uint256 accRewardPerST = pool.accRewardPerST;
        uint256 totalSupply = pool.stTokenAmount;
        if(totalSupply > 0 && block.timestamp > pool.lastRewardBlock && )
    }
}