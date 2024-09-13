//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMaxStake {

    struct User {
        uint256 stAmount;
        uint256 finishedAmount;
        uint256 pendingAmount;
        uint256 tokensUnlockTime;
        address [] salesRegistered;
    }

        struct Pool {
        address stTokenAddress;
        uint256 poolWeight;
        uint256 lastRewardBlock;
        // 每个代币奖励质押B2份额
        uint256 accB2PerST;
        uint256 stTokenAmount;
        uint256 minDepositAmount;
        uint256 minUnstakeAmount;
        uint256 lendingAmount;
        uint256 borrowingAmount;
        uint256 lendingRewardAmount;
        uint256 borrowingRewardAmount;
    }

    event Deposit(uint256 _pid,uint256 amount);
    event Withdraw(uint256 _pid,uint256 amount);
    event Reward(uint256 _pid);
    event WithdrawPaused();
    event ClaimPaused();
    event WithdrawUnPaused();
    event ClaimUnPaused();
    event UpdatePool(uint256 idx, uint256 lastRewardBlock, uint256 reward);
    event DepositLend(uint256 _pid,uint _amount);
    event WithdrawLend(uint256 _pid,uint _amount);
    event ClaimLend(uint256 _pid);
    event DepositBorrow(uint256 _pid,uint _amount);
    event WithdrawBorrow(uint256 _pid,uint _amount);
    event ClaimBorrow(uint256 _pid);
    event Redeem(uint256 _pid,uint256 borrowAmt,uint256 collateralReward,uint256 accumulateInterest,address receiver);
    event Settle(uint256 _pid,uint256 landingAmount,uint256 landingRewardAmount,uint256 totalInterest,address receiver);
}