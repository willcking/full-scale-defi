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
    bool public withdrawPaused;
    bool public claimPaused;

    Pool[] public pools;    
    // User deposits in the liquidity pool
    mapping(uint256 => mapping(address => User)) userInfo;

    modifier withdrawUnPaused () {
        require(!withdrawPaused, "withdraw is Paused");
        _;
    }

    modifier claimUnPaused () {
        require(!claimPaused, "claim is Paused");
        _;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Invalid Operator");
        _;
    }
    
    function initialize(address _rewardstAddress, uint256 _rewardPerSecond, uint256 _startTimeStamp, uint256 _endTimeStamp) external initializer {
        require(_startTimeStamp < _endTimeStamp, "Invalid time");
        require(_endTimeStamp > block.timestamp, "Invalid end time");
        rewardToken = IERC20(_rewardstAddress);
        rewardPerSecond = _rewardPerSecond;
        startTimeStamp = _startTimeStamp;
        endTimeStamp = _endTimeStamp;
        _owner = msg.sender;

        __UUPSUpgradeable_init();
    }

    // Add liquidity pool
    function addPool(address tokeAddr, uint256 poolWeight, ) external onlyOwner {
        
    }

////////////////////////////////////////    Staking    ////////////////////////////////////////

    function pauseWithdraw() external onlyOwner withdrawUnPaused {
        withdrawPaused = true;

        emit WithdrawPaused();
    }

    function pauseClaim() external onlyOwner claimUnPaused {
        claimPaused = true;

        emit ClaimPaused();
    }

    function unPauseWithdraw() external onlyOwner {
        require(withdrawPaused, "withdraw is unPaused");
        withdrawPaused = false;

        emit WithdrawUnPaused();
    }

    function unPauseClaim() external onlyOwner {
        require(claimPaused, "claim is unPaused");
        claimPaused = false;

        emit ClaimUnPaused();
    }

    function massUpdatePools() internal {
        for (uint i = 0; i < pools.length; ++i) {
            updatePool(i);
        }
    }

    // Inject rewardToken into the pool
    function fund(uint256 _amount) external onlyOwner {
        require(block.timestamp < endTimeStamp, "Time is too late");
        totalRewards += _amount;
        endTimeStamp += _amount / rewardPerSecond;
        ierc20B2.transferFrom(msg.sender, address(this), _amount);
    }

    // Update liquidity pool data and call when liquidity changes.
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

    function Stake(uint256 pid, uint256 amount) external claimUnPaused {
        require(block.timestamp < endTimeStamp, "Staking has ended");
        Pool storage pool = pools[pid];
        require(amount >= pool.minDepositAmount, "Amount less than limit");

        User storage user = userInfo[pid][msg.sender];

        // Update data every time user stake
        updatePool(pid);

        // claim reward
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

    function Withdraw(uint256 pid, uint256 amount) external claimUnPaused withdrawUnPaused {
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

    function claimReward(uint256 pid) external claimUnPaused {
        User storage user = userInfo[pid][msg.sender];
        
        uint256 reward = pending(pid, msg.sender);
        user.finishedAmount += reward;
        user.pendingAmount = 0;
        rewardToken.transfer(msg.sender, reward);

        emit Reward(pid);
    }

    function pending(uint256 pid, address user) internal view returns(uint256) {
        User memory user = userInfo[pid][user];
        Pool memory pool = pools[pid];

        uint256 accRewardPerST = pool.accRewardPerST;
        uint256 totalSupply = pool.stTokenAmount;

        return user.stAmount * (accRewardPerST) / (1e36) - (user.finishedAmount);
    }

////////////////////////////////////////  Borrowing and Loaning  ////////////////////////////////////////
}