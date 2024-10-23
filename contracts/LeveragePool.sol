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

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;

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
    mapping(address => uint256) lastFundingTimes;
    mapping(address => uint256) feeReserves;
    mapping(address => uint256) guaranteedUsds;
    mapping(address => uint256) globalShortSizes;
    mapping(address => uint256) globalShortAveragePrices; 

    event UpdateFundingRate(address collateralToken, uint256 cumulativeFundRate);
    event IncreaseReservedAmount(address collateralToken, uint256 amount);
    event IncreaseGuaranteedUsds(address collateralToken, uint256 amount);
    event DecreaseGuaranteedUsds(address collateralToken, uint256 amount);
    event IncreasePoolAmount(address collateralToken, uint256 amount);
    event DecreasePoolAmount(address collateralToken, uint256 amount);
    event IncreaseGlobalShortSize(address collateralToken, uint256 amount);
    event CollectMarginFees(address collateralToken, uint256 feeUsd, uint256 feeTokens);
    event UpdatePosition(bytes32 key, uint256 positionSize, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, uint256 price);
    event IncreasePosition(bytes32 key, address _account, address collateralToken, address indexToken, uint256 collateralDeltaUsd, uint256 sizeDelta, bool isLong, uint256 price, uint256 fee);
 
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
            position.averagePrice = getNextAveragePrice(indexToken, position.positionSize, position.averagePrice, isLong, price, sizeDelta, position.lastUpdateTime);
        }

        uint256 fee = collectMarginFee(collateralToken, sizeDelta, position.positionSize, position.entryFundingRate);
        uint256 collateralDelta = transferIn(collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(collateralToken, collateralDelta);
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
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            increaseGuaranteedUsd(collateralToken, sizeDelta + fee);
            decreaseGuaranteedUsd(collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            increasePoolAmount(collateralToken, collateralDelta);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            decreasePoolAmount(collateralToken, usdToTokenMin(collateralToken, fee));
        } else {
            // Update short global average price
            if (globalShortSizes[indexToken] == 0) {
                globalShortAveragePrices[indexToken] = price;
            } else {
                globalShortAveragePrices[indexToken] = getNextGlobalShortAveragePrice(indexToken, price, sizeDelta);
            }
            increaseGlobalShortSize(indexToken, sizeDelta);
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

    function increaseGuaranteedUsd(address collateralToken, uint256 amount) private {
        guaranteedUsds[collateralToken] += amount;
        emit IncreaseGuaranteedUsds(collateralToken, amount);
    }

    function decreaseGuaranteedUsd(address collateralToken, uint256 amount) private {
        guaranteedUsds[collateralToken] -= amount;
        emit DecreaseGuaranteedUsds(collateralToken, amount);
    }

    function increasePoolAmount(address collateralToken, uint256 amount) private {
        poolAmounts[collateralToken] += amount;
        emit IncreasePoolAmount(collateralToken, amount);
     }

    function decreasePoolAmount(address collateralToken, uint256 amount) private {
        poolAmounts[collateralToken] -= amount;
        emit DecreasePoolAmount(collateralToken, amount);
     }

    function increaseGlobalShortSize(address collateralToken, uint256 amount) private {
        globalShortSizes[collateralToken] += amount;
        emit IncreaseGlobalShortSize(collateralToken,amount);
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
    
    function validatePosition(uint256 positionSize, uint256 collateral) private pure {
        if (positionSize == 0) {
            require(collateral == 0, "init Position collateral must be 0");
            return;
        }
        require(positionSize >= collateral, "the positionSize should great than collateral");
    }    

    function collectMarginFee(address collateralToken, uint256 sizeDelta, uint256 positionSize, uint256 entryFundingRate) private returns(uint256) {
        uint256 feeUsd = getPositionFee(sizeDelta);
        uint256 fundingFee = getFundingFee(collateralToken, positionSize, entryFundingRate);

        feeUsd = feeUsd-fundingFee;

        uint256 feeTokens = usdToTokenMin(collateralToken, feeUsd);
        feeReserves[collateralToken] = feeReserves[collateralToken] + feeTokens;

        emit CollectMarginFees(collateralToken, feeUsd, feeTokens);
        return feeUsd;
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

    function getPositionFee(uint256 sizeDelta) internal view returns(uint256) {
        if (sizeDelta == 0) {
            return 0; 
        }
        uint256 afterFeeUsd = sizeDelta*(BASIS_POINTS_DIVISOR-(marginFeeBasisPoints))/(BASIS_POINTS_DIVISOR);
        return sizeDelta - afterFeeUsd;
    }

    function getFundingFee(address collateralToken, uint256 positionSize, uint256 entryFundingRate) internal view returns(uint256) {
        if (positionSize == 0) { 
            return 0;
        }

        uint256 fundingRate = cumulativeFundingRates[collateralToken] - entryFundingRate;
        if (fundingRate == 0) { 
            return 0; 
        }

        return positionSize * fundingRate / FUNDING_RATE_PRECISION;
    }

    function tokenToUsdMin(address collateralToken, uint256 amount) internal view returns(uint256) {
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

    function usdToTokenMin(address collateralToken, uint256 amount) internal view returns(uint256){
        if(amount == 0){
            return 0;
        }
        uint256 price = getMaxPrice(collateralToken);
        uint256 decimal = tokenDecimal[collateralToken];
        return amount * (10 ** decimal) / price;
    }

    function validateLiquidation(address account, address collateralToken, address indexToken, bool isLong) internal view returns (uint256,uint256){
        Position storage position = positions[getPositionKey(account, collateralToken, indexToken, isLong)];
        (bool hasProfit, uint256 delta) = getDelta(indexToken, position.positionSize, position.averagePrice, isLong, position.sizeDelta, position.lastUpdateTime);

        uint256 marginFees = getFundingFee(collateralToken, position.positionSize, position.entryFundingRate);
        marginFees = marginFees + getPositionFee(position.positionSize);

        if (!hasProfit && position.collateral < delta) {
            revert("losses exceed collateral");
        }

        // Check if loss exceeds collateral
        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral - delta;
        }
        // Calculate whether the remaining collateral is sufficient to cover the position fee
        if (remainingCollateral < marginFees) {
            revert("fees exceed collateral");
        }
        // Calculate whether the remaining collateral is sufficient to pay the liquidation fee
        if (remainingCollateral < marginFees + liquidationFeeUsd) {
            revert("liquidation fees exceed collateral");
        }
        // Check if the maximum leverage is exceeded
        if (remainingCollateral * maxLeverage < position.positionSize * BASIS_POINTS_DIVISOR) {
            revert("Vault: maxLeverage exceeded");
        }

        return (0, marginFees);
    }

    function getNextAveragePrice(address indexToken, uint256 positionSize, uint256 averagePrice, bool isLong, uint256 price, uint256 sizeDelta, uint256 lastUpdateTime) internal view returns(uint256) {
        (bool hasProfit, uint256 delta) = getDelta(indexToken, positionSize, averagePrice, isLong, lastUpdateTime);
        uint256 diverse;
        uint256 nextSize = positionSize + sizeDelta;
        if(isLong){
            diverse = hasProfit ? nextSize + delta : nextSize-delta;
        }else{
            diverse = hasProfit ? nextSize - delta : nextSize+delta;
        }

        return price * nextSize / diverse;
    }

    function getDelta(address indexToken, uint256 positionSize, uint256 averagePrice, bool isLong, uint256 sizeDelta, uint256 lastUpdateTime) internal view returns(bool, uint256) {
        require(averagePrice > 0, "averagePrice must great than 0");
        uint256 price = isLong ? getMinPrice(indexToken) : getMaxPrice(indexToken);
        uint256 priceDelta = averagePrice > price ? averagePrice-price : price - averagePrice;
        uint256 delta = positionSize * priceDelta/ averagePrice;

        bool hasProfit;

        if (isLong) { 
            hasProfit = price > averagePrice;
        } else {
            hasProfit = averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        uint256 minBps = block.timestamp > lastUpdateTime+(minProfitTime) ? 0 : minProfitBasisPoints[indexToken];
        if (hasProfit && delta*(BASIS_POINTS_DIVISOR) <= positionSize*(minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    function updateCumulativeFundingRate(address collateralToken) internal {
        require(fundingInterval > 0, 'fundingInterval didnt init');
        if(!shouldUpdate) {
            return;
        }
        // Initialize lastFundingTimes
        if (lastFundingTimes[collateralToken] == 0) {
            lastFundingTimes[collateralToken] = block.timestamp/fundingInterval*fundingInterval;
            return;
        }
        // Check if the next funding interval has arrived
        if (lastFundingTimes[collateralToken] +fundingInterval  > block.timestamp) {
            return;
        }

        uint256 fundingRate = getNextFundingRate(collateralToken);
        cumulativeFundingRates[collateralToken] = cumulativeFundingRates[collateralToken]+fundingRate; 
        lastFundingTimes[collateralToken] = block.timestamp/(fundingInterval)*(fundingInterval);

        emit UpdateFundingRate(collateralToken, cumulativeFundingRates[collateralToken]);

    }

    function getNextFundingRate(address collateralToken) internal view returns(uint256) {
        uint256 intervals = (block.timestamp-lastFundingTimes[collateralToken])/(fundingInterval);
        uint256 poolAmount = poolAmounts[collateralToken];
        if (poolAmount == 0) { return 0; }
        uint256 _fundingRateFactor = stableTokens[collateralToken] ? stableFundingRateFactor : fundingRateFactor;
        // Interest needs to be added
        return _fundingRateFactor*(reservedAmounts[collateralToken])*(intervals)/(poolAmount);
    }

    function getNextGlobalShortAveragePrice(address indexToken, uint256 nextPrice, uint256 sizeDelta) internal view returns(uint256) {
        uint256 size = globalShortSizes[indexToken];
        uint256 averagePrice = globalShortAveragePrices[indexToken];
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice- nextPrice : nextPrice - averagePrice;
        uint256 delta = size*(priceDelta)/(averagePrice);
        bool hasProfit = averagePrice > nextPrice;

        uint256 nextSize = size*(sizeDelta); 
        uint256 divisor = hasProfit ? nextSize- delta : nextSize + delta;

        return nextPrice * nextSize / divisor;
    }

   function _authorizeUpgrade(address newImplementation) internal override{

   }
}

