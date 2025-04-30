// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RewardToken} from "../token/RewardToken.sol";
import {MaxStake} from "../MaxStake.sol";
import {CupToken} from "../token/CupToken.sol";
import {SalesFactory} from "../factory/SalesFactory.sol";
import {Admin} from "../Admin.sol";

contract MTest is Test {

    uint256 mainnetFork;
    address account1;
    address _pancakeFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address _pancakeRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    uint256 constant ONE_DAY = 86400;

    function setUp() public {

        mainnetFork = vm.createFork("https://bsc-dataseed.bnbchain.org");

    }


    function test_pancake() public {
        vm.selectFork(mainnetFork);
        //deployed mint token
        address account = createAccount("tom");
        address jackAccount = createAccount("jack");
        vm.startPrank(account);

        RewardToken reward = new RewardToken();
        reward.mint(account, 10e37);
        MaxStake maxstake = new MaxStake();
        maxstake.initialize(address(reward), 10, block.timestamp, block.timestamp + ONE_DAY);

        address maxstakeAddress = address(maxstake);
        console.log("maxstake:", maxstakeAddress);
        reward.approve(maxstakeAddress, 10e37);
        maxstake.fund(10e37);
        CupToken cupToken = new CupToken();
        cupToken.mint(account, 10e37);
        SalesFactory saleFactory = new SalesFactory(maxstakeAddress);


        address[] memory _admins = new address[](1);
        _admins[0] = account;
        saleFactory.init(_admins);
        saleFactory.deploySale(account);

        address saleAddress = saleFactory.allSales(0);

        console.log("saleAddress:", saleAddress);
        maxstake.add(
            address(cupToken),
            false, 1, 1e18, 1e18
        );
        cupToken.mint(jackAccount, 1e18);
        vm.stopPrank();
        vm.startPrank(jackAccount);
        cupToken.approve(maxstakeAddress, 1e18);
        maxstake.deposit(0, 1e18);
        maxstake.reward(0);
        vm.stopPrank();
    }


    function createAccount(string memory name) public returns (address) {
        address test = makeAddr(name);
        deal(WBNB, test, 10 ether);
        deal(BUSD, test, 1000 ether);
        vm.deal(test, 100 ether);
        return test;
    }


}

