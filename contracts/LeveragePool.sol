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
        uint256 entryFundingRate;
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
    mapping(bytes32 => Position) positions;
    mapping(address => uint256) tokenBalance;
    mapping(address => uint256) cumulativeFundingRates;
    mapping(address => uint256) reservedAmounts;
    mapping(address => uint256) poolAmounts;

    event IncreaseReservedAmount(address collateralToken, uint256 amount);
    event IncreasePosition(bytes32 key, address _account, address _collateralToken, address _indexToken, uint256 _collateralDeltaUsd, uint256 _sizeDelta, bool _isLong, uint256 _price, uint256 fee);
 
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
        
        uint256 price = isLong ? getMaxPrice(indexToken) : getMinPrice(indexToken);

        if(position.positionSize == 0) {
            position.averagePrice =  price;
        }

        if(position.positionSize > 0 && sizeDelta > 0) {
            //todo
        }

        uint256 fee = collectMarginFee(collateralToken, sizeDelta, position.positionSize, position.entryFundingRate);
        uint256 collateralDelta = transferIn(collateralToken);
        uint256 collateralDeltaUsd = TokenToUsd(collateralToken, collateralDelta);
        position.collateral = position.collateral + collateralDeltaUsd;
        require(position.collateral >= fee, "collateral must great than fee");
        position.collateral = position.collateral - fee;
        position.entryFundingRate = cumulativeFundingRates[collateralToken];
        position.positionSize = position.positionSize + sizeDelta;
        position.lastUpdateTime = block.timestamp;

        require(position.positionSize > 0, 'positionSize cant be 0');
        validatePosition(position.positionSize, position.collateral); 
        validateLiquidation(account, collateralToken, indexToken, isLong);
        uint256 reserveDelta = usdToTokenMax(collateralToken, sizeDelta);
        position.reserveAmount = position.reserveAmount + reserveDelta;
        increaseReservedAmount(collateralToken, reserveDelta);

        if(isLong) {
            //todo
        } else {
            //todo
        }

        emit IncreasePosition(key, account, collateralToken, indexToken, collateralDeltaUsd, sizeDelta, isLong, price, fee);
        emit UpdatePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, price);
    }

    function decreasePosition() external nonReentrant {

    }

    function liquidatePosition() external nonReentrant {
        
    }

    function increaseReservedAmount(address collateralToken, uint256 amount) private {
        reservedAmounts[collateralToken] += amount;
        require(reservedAmounts[collateralToken] <= poolAmounts[collateralToken],"the reserve amount must less or equal than pool amount");
        emit IncreaseReservedAmount(collateralToken, amount);
    }

    function getMaxPrice(address indexToken) internal view returns(uint256) {
        return iPoolPriceFeed.getPrice(indexToken , true, includeAmmPrice);
    }

    function getMinPrice(address indexToken) internal view returns(uint256) {
        return iPoolPriceFeed.getPrice(indexToken , false, includeAmmPrice);
    }

    function validateGasPrice() private view {
        require(tx.gasprice < maxGasPrice, 'the gas overFlow');
    }

    function transferIn(address collateralToken) private returns(uint256) {
        uint256 preBalance = tokenBalance[collateralToken];
        uint256 currentBalance = IERC20(collateralToken).balanceOf(address(this));

        tokenBalance[collateralToken] = currentBalance;
        return currentBalance-preBalance;
    }
    
    function validatePosition(uint256 _positionSize, uint256 _collateral) private pure {
        if (_positionSize == 0) {
            require(_collateral == 0, "init Position collateral must be 0");
            return;
        }
        require(_positionSize >= _collateral, "the positionSize should great than collateral");
    }    

    function collectMarginFee(address collateralToken, uint256 sizeDelta, uint256 positionSize, uint256 entryFundingRate) private returns(uint256) {
        //todo
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
        return keccak256(abi.encodePacked(account, collateralToken, indexToken, isLong));
    }

    function TokenToUsd(address collateralToken, uint256 amount) internal view returns(uint256) {
        if(amount == 0){
            return 0;
        }
        uint256 price = getMinPrice(collateralToken);
        uint256 decimal = tokenDecimal[collateralToken];
        return price * amount / (10 ** decimal);
    }

    function usdToTokenMax(address collateralToken, uint256 amount) internal view returns (uint256){
        if(amount == 0){
            return 0;
        }
        uint256 price = getMinPrice(collateralToken);
        uint256 decimal = tokenDecimal[collateralToken];
        return amount * (10 ** decimal) / price;
    }

    function validateLiquidation(address account, address collateralToken, address indexToken, bool isLong) internal view returns (uint256,uint256){
        //todo
    }

    function updateCumulativeFundingRate(address collateralToken) internal {
        //todo
    }

   function _authorizeUpgrade(address newImplementation) internal override{

   }
}

