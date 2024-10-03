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
    uint256 public lendingInterestRate; // Annual interest rate
    uint256 public borrowingInterestRate; // Annual interest rate
    uint256 public minLending;
    uint256 public minCollateral;
    uint256 public collateralRate;
    uint256 public paidout;
    address private _owner;
    bool public withdrawPaused;
    bool public claimPaused;

    Pool[] public pools;    
    // User deposits in the liquidity pool
    mapping(uint256 => mapping(address => User)) userInfo;
    // Record the added liquidity pool
    mapping(address => bool) poolList;
    // Record user lending information
    mapping(address => mapping(address => LendingInfo)) lendingUserInfo;
    // Record user borrowing information
    mapping(address => mapping(address => BorrowingInfo)) borrowingUserInfo;

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
    function addPool(address _tokeAddr, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _minUnstakeAmount, bool isUpdata) external onlyOwner {
        require(_tokeAddr != address(0), "Invalid token address");
        require(_poolWeight > 0, "Pool weight must be greater than zero");
        require(_minDepositAmount > 0, "Min deposit amount must be greater than zero");
        require(_minUnstakeAmount > 0, "Min unstake amount must be greater than zero");
        require(!poolList[_tokeAddr], "Liquidity pools have been added");

        if(isUpdata) {
            massUpdatePools();
        }

        uint256 _lastRewardBlock = block.timestamp > startTimeStamp ? block.timestamp : startTimeStamp;

        pools.push(Pool({
            stTokenAddress: _tokeAddr,
            poolWeight: _poolWeight,
            lastRewardBlock: _lastRewardBlock,
            accRewardPerST: 0,
            stTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            minUnstakeAmount: _minUnstakeAmount,
            lendingAmount: 0,
            borrowingAmount: 0
        }));

        totalAllocPoint += _poolWeight;
        poolList[_tokeAddr] = true;
    }

    function setPoolWeight(uint256 pid, uint256 newPoolWeight, bool isUpdata) public onlyOwner {
        if(isUpdata) {
            massUpdatePools();
        }
        Pool storage pool = pools[pid];
        totalAllocPoint = totalAllocPoint - pool.poolWeight + newPoolWeight;
        pool.poolWeight = newPoolWeight;
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
    function fund(uint256 amount) external onlyOwner {
        require(block.timestamp < endTimeStamp, "Time is too late");
        totalRewards += amount;
        endTimeStamp += amount / rewardPerSecond;
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    // Update liquidity pool data and call when liquidity changes.
    function updatePool(uint256 pid) internal {
        Pool storage pool = pools[pid];

        uint256 lastTime = block.timestamp < endTimeStamp ? block.timestamp : endTimeStamp;
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

    function stake(uint256 pid, uint256 amount) external claimUnPaused {
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

    function withdraw(uint256 pid, uint256 amount) external claimUnPaused withdrawUnPaused {
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

    function pending(uint256 pid, address userAddress) internal view returns(uint256) {
        User memory user = userInfo[pid][userAddress];
        Pool memory pool = pools[pid];

        uint256 accRewardPerST = pool.accRewardPerST;
        uint256 totalSupply = pool.stTokenAmount;

        return user.stAmount * (accRewardPerST) / (1e36) - (user.finishedAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {

    }
////////////////////////////////////////  Borrowing and Loaning  ////////////////////////////////////////

    function depositLend(uint256 pid, uint256 amount) external nonReentrant {
        Pool storage pool = pools[pid];
        LendingInfo storage lendingInfo = lendingUserInfo[pool.stTokenAddress][msg.sender];

        // If the user already has a loan record, calculate the interest 
        if(lendingInfo.lendingAmount > 0) {
            uint256 lendingTimePeriod = block.timestamp - lendingInfo.lendingLastTime;
            lendingInfo.accumulateInterest += lendingInfo.lendingAmount * lendingTimePeriod * lendingInterestRate * 1e36 / (365 * 24 * 3600);
        }

        lendingInfo.lendingAmount += amount;
        lendingInfo.lendingLastTime = block.timestamp;
        pool.lendingAmount += amount;

        IERC20(pool.stTokenAddress).transferFrom(msg.sender, address(this), amount);

        emit DepositLend(pid, amount);
    }
    // Withdraw staked token for lending 
    function withdrawToLend(uint256 pid, uint256 amount) external nonReentrant withdrawUnPaused {
        User storage user = userInfo[pid][msg.sender];
        require(user.stAmount > amount, "Staked amount less than amount");

        Pool storage pool = pools[pid];
        updatePool(pid);

        uint256 reward = pending(pid, msg.sender);
        user.finishedAmount += reward;
        user.pendingAmount = 0;
        rewardToken.transfer(msg.sender, reward);

        user.stAmount -= amount;
        pool.stTokenAmount -= amount;

        LendingInfo storage lendingInfo = lendingUserInfo[pool.stTokenAddress][msg.sender];

        // If the user already has a loan record, calculate the interest 
        if(lendingInfo.lendingAmount > 0) {
            uint256 lendingTimePeriod = block.timestamp - lendingInfo.lendingLastTime;
            lendingInfo.accumulateInterest += lendingInfo.lendingAmount * lendingTimePeriod * lendingInterestRate * 1e36 / (365 * 24 * 3600);
        }

        lendingInfo.lendingAmount += amount;
        lendingInfo.lendingLastTime = block.timestamp;
        pool.lendingAmount += amount;

        emit WithdrawToLend(pid, amount);
    }

    function borrow(uint256 pid, uint256 amount) external nonReentrant {
        Pool storage pool = pools[pid];
        uint256 canBorrowAmt = getCanBorrowAmt(pid);

        BorrowingInfo storage borrowInfo = borrowingUserInfo[pool.stTokenAddress][msg.sender];
        require(canBorrowAmt - borrowInfo.borrowingAmount > amount,"the borrowAmt overflow");
        require(pool.lendingAmount - pool.borrowingAmount > amount, "total borrow amount must less than total lending");


        //// If there is a record of lending before, calculate the interest first
        if(borrowInfo.borrowingAmount > 0){
            uint256 borrowTimePeriod = block.timestamp - borrowInfo.borrowLastTime;
            borrowInfo.accumulateInterest += borrowInfo.borrowingAmount * borrowTimePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);
        }

        borrowInfo.borrowingAmount += amount;
        borrowInfo.borrowLastTime = block.timestamp;

        pool.borrowingAmount += amount;

        IERC20(pool.stTokenAddress).transfer(msg.sender,amount);

        emit Borrow(pid, amount);
    }

    function settle(uint256 pid) external nonReentrant {
        Pool storage pool = pools[pid];
        LendingInfo storage lendingInfo = lendingUserInfo[pool.stTokenAddress][msg.sender];

        uint256 lendingAmount = lendingInfo.lendingAmount;
        uint256 lendingTimePeriod = block.timestamp - lendingInfo.lendingLastTime;
        uint256 accumulateInterest = lendingInfo.accumulateInterest + lendingInfo.lendingAmount * lendingTimePeriod * lendingInterestRate * 1e36/(365 * 24 * 3600);

        pool.lendingAmount -= lendingInfo.lendingAmount;

        lendingInfo.lendingAmount = 0;
        lendingInfo.lendingLastTime = block.timestamp;

        IERC20(pool.stTokenAddress).transfer(msg.sender,lendingAmount);
        interestToken.transfer(msg.sender, accumulateInterest);

        emit Settle(pid, lendingAmount, accumulateInterest, msg.sender);
    }

    function redeem(uint256 pid) external nonReentrant {
        Pool storage pool = pools[pid];
        BorrowingInfo storage borrowInfo = borrowingUserInfo[pool.stTokenAddress][msg.sender];

        uint256 borrowingAmount = borrowInfo.borrowingAmount;
        uint256 borrowTimePeriod = block.timestamp - borrowInfo.borrowLastTime;
        uint256 accumulateInterest = borrowInfo.accumulateInterest + borrowInfo.borrowingAmount * borrowTimePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);

        pool.borrowingAmount -= borrowInfo.borrowingAmount;

        borrowInfo.borrowingAmount = 0;
        borrowInfo.accumulateInterest = 0;
        borrowInfo.borrowLastTime = block.timestamp; 

        interestToken.transferFrom(msg.sender, address(this), accumulateInterest);
        IERC20(pool.stTokenAddress).transferFrom(msg.sender, address(this), borrowingAmount);

        emit Redeem(pid, borrowingAmount, accumulateInterest, msg.sender);
    }
    function setInterestParams(address _interestToken, uint256 _initInterest, uint256 _minLending, uint256 _collateralRate, uint256 _mincollateral) external onlyOwner {
        require(_interestToken != address(0), "invalid Token address");
        require(address(interestToken) == address(0), "the interestToken have alread seted");
        require(_initInterest > 0, "initInterest must great than 0");

        interestToken = IERC20(_interestToken);
        initInterest = _initInterest;
        minLending = _minLending;
        collateralRate = _collateralRate;
        minCollateral = _mincollateral;

    }

    function setInterestRate(uint256 _lendingInterestRate, uint256 _borrowingInterestRate) external onlyOwner {
        require(_lendingInterestRate < _borrowingInterestRate, "the borrowingInterest must great than lendingInterest");
        require(_lendingInterestRate > 0 && _borrowingInterestRate > 0, "the interest must great than 0");

        lendingInterestRate = _lendingInterestRate;
        borrowingInterestRate = _borrowingInterestRate;
    }

    function getCanBorrowAmt(uint256 pid) public view returns(uint256) {
        User storage user = userInfo[pid][msg.sender];
        uint256 userCanBorrowAmt = user.stAmount * collateralRate /100;
        return userCanBorrowAmt;
    }
}
