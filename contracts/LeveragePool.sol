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

    IPoolPriceFeed iPoolPriceFeed;
    bool public isLeverageEnabled;
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

    mapping(address => bool) tokenWhiteList;
    mapping(address => bool) stableTokens;
    mapping(address => bool) shortableTokens;
    mapping(address => bool) isLiquidator;
    mapping(address => uint256) minProfitBasisPoints;
    mapping(address => uint256) tokenDecimal;
    mapping(bytes32=>Position) positions;
 
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

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyAdmin {
        maxGasPrice = _maxGasPrice;
    }

    function addWhiteList(address _whiteAddress) external onlyAdmin {
        tokenWhiteList[_whiteAddress] = true;
    }

    function setStableToken(address _stableToken) external onlyAdmin {
        stableTokens[_stableToken] = true;
    }

    function setShortableToken(address _shortableToken) external onlyAdmin {
        shortableTokens[_shortableToken] = true;
    }

    function setIsLiquidator(address _address) external onlyAdmin {
        isLiquidator[_address] = true;
    }

    function setMinProfitBasisPoints(address _token,uint256 _points) external onlyAdmin {
        minProfitBasisPoints[_token] = _points;
    }

    function setTokenDecimals(address _token,uint256 _decimal) external onlyAdmin {
        tokenDecimal[_token] = _decimal;
    }

    function setShouldUpdateRate(bool _shouldUpdate) external onlyAdmin {
        shouldUpdate = _shouldUpdate;
    }

    function setFundingInterval(uint256 _fundingInterval) external onlyAdmin {
        fundingInterval = _fundingInterval;
    }

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external onlyAdmin {
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }

    function setStableFundingRateFactor(uint256 _stableFundingRateFactor) external onlyAdmin {
        stableFundingRateFactor = _stableFundingRateFactor;
    }

    function setFundingRateFactor(uint256 _fundingRateFactor) external onlyAdmin {
        fundingRateFactor = _fundingRateFactor;
    }

    function setMinProfitTime(uint256 _minProfitTime) external onlyAdmin {
        minProfitTime = _minProfitTime;
    }

    function setMarginFeeBasisPoints(uint256 _marginFeeBasisPoints) external onlyAdmin {
       marginFeeBasisPoints = _marginFeeBasisPoints;
    }

    function setLiquidationFeeUsd(uint256 _liquidationFeeUsd ) external  onlyAdmin {
        liquidationFeeUsd = _liquidationFeeUsd;
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyAdmin {
        maxLeverage = _maxLeverage;
    }

    /**
    * @param account corresponding account
    * @param collateralToken collateral token
    * @param indexToken i
    * @param sizeDelta increasing position
    * @param isLong true for long position, false for short position
    */
    function increasePosition(address account, address collateralToken, address indexToken, uint256 sizeDelta, bool isLong) external nonReentrant {
        require(isLeverageEnabled, 'leverage should be turn on');

        validateGasPrice();

        validateTokens(collateralToken, indexToken, isLong);

        updateCumulativeFundingRate(collateralToken);

        bytes key = getPositionKey(account, collateralToken, indexToken, isLong);
        Position storage position = positions[key];
        
    }

    function decreasePosition() external nonReentrant {

    }

    function liquidatePosition() external nonReentrant {
        
    }

    function validateGasPrice() private view {
        require(tx.gasprice < maxGasPrice, 'the gas overFlow');
    }

    function validateTokens(address collateralToken, address indexToken, bool isLong) private view {
        if(isLong){
            require(collateralToken == indexToken, "collateral token must equal target token");
            require(tokenWhiteList[collateralToken], "collateral token not in whiteList");
            require(!stableTokens[collateralToken], "token can't be stable");
            return;
        }

        require(tokenWhiteList[collateralToken], 'collateral token not in whiteList');
        require(stableTokens[collateralToken], 'collateral token should be stable');
        require(!stableTokens[indexToken], 'indexToken cant be stable');
        require(shortableTokens[indexToken], 'indexToken cant be shortable');
    }

    function getPositionKey(address account, address collateralToken, address indexToken, bool isLong) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(account, collateralToken, indexToken, isLong))
    }

    function updateCumulativeFundingRate(address collateralToken) internal {
        //todo
    }

   function _authorizeUpgrade(address newImplementation) internal override{

   }
}

