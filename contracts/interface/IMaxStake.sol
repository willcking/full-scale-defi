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
        uint256 accRewardPerST;
        uint256 stTokenAmount;
        uint256 minDepositAmount;
        uint256 minUnstakeAmount;
        uint256 lendingAmount;
        uint256 borrowingAmount;
    }

    struct LendingInfo {
        uint256 lendingAmount;
        uint256 lendingLastTime;
        uint256 accumulateInterest;
    }

    struct BorrowingInfo {
        uint256 borrowingAmount;
        uint256 borrowLastTime;
        uint256 accumulateInterest;
    }

    event Stake(uint256 pid,uint256 amount);
    event Withdraw(uint256 pid,uint256 amount);
    event Reward(uint256 pid);
    event WithdrawPaused();
    event ClaimPaused();
    event WithdrawUnPaused();
    event ClaimUnPaused();
    event UpdatePool(uint256 pid, uint256 lastRewardBlock, uint256 reward);
    event DepositLend(uint256 pid,uint amount);
    event WithdrawToLend(uint256 pid,uint amount);
    event ClaimLend(uint256 pid);
    event Borrow(uint256 pid,uint amount);
    event WithdrawBorrow(uint256 pid,uint amount);
    event ClaimBorrow(uint256 pid);
    event Redeem(uint256 pid,uint256 borrowingAmount,uint256 accumulateInterest,address receiver);
    event Settle(uint256 pid,uint256 landingAmount,uint256 totalInterest,address receiver);
}