//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interface/IPoolPriceFeed.sol";
import "./utils/ReentrancyGuard.sol";
import "./interface/IERC20.sol";
import "./Admin.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract LeveragePool is ReentrancyGuard, Admin, Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    
    struct Position {
        uint256 positionSize;
        uint256 collateral;
        uint256 averagePrice;
        uint256 lastUpdateTime;
    }
    bool public shouldUpdate;
    bool public includeAmmPrice;
    bool public inPrivateLiquidationMode;
    uint256 public maxGasPrice;
    uint256 public fundingInterval;
    uint256 public stableFundingRateFactor;
    uint256 public fundingRateFactor;
    uint256 public minProfitTime;
    uint256 public marginFeeBasisPoints;
    uint256 public liquidationFeeUsd;
    uint256 public maxLeverage;
    IPoolPriceFeed iPoolPriceFeed;

    function initialize(address _iPoolPriceFeed, uint256 _maxGasPreice, bool _shouldUpdate, bool _includeAmmPrice, bool _inPrivateLiquidationMode) external initializer {
        iPoolPriceFeed = IPoolPriceFeed(_iPoolPriceFeed);
        maxGasPrice = _maxGasPreice;
        shouldUpdate = _shouldUpdate;
        includeAmmPrice = _includeAmmPrice;
        inPrivateLiquidationMode = _inPrivateLiquidationMode;

        addAdmin(msg.sender);
        __UUPSUpgradeable_init();
    }

    function setConfig(uint256 _fundingInterval, uint256 _stableFundingRateFactor, uint256 _fundingRateFactor, uint256 _minProfitTime, uint256 _marginFeeBasisPoints, uint256 _liquidationFeeUsd, uint256 _maxLeverage) external onlyAdmin {
        fundingInterval = _fundingInterval;
        stableFundingRateFactor = _stableFundingRateFactor;
        fundingRateFactor = _fundingRateFactor;
        minProfitTime = _minProfitTime;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        maxLeverage = _maxLeverage;
    }

    
   function _authorizeUpgrade(address newImplementation) internal override{

   }
}