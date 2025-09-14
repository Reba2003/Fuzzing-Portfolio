// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Mock interfaces for testing
interface IERC4626 {
    function convertToAssets(uint256 shares) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// Mock Chainlink Oracle that can simulate stale data
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 public price;
    uint256 public lastUpdated;
    uint8 public decimals_;
    bool public isStale;
    uint256 public stalenessThreshold = 3600; // 1 hour
    
    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals_ = _decimals;
        lastUpdated = block.timestamp;
    }
    
    function decimals() external view override returns (uint8) {
        return decimals_;
    }
    
    function description() external pure override returns (string memory) {
        return "Mock Oracle";
    }
    
    function version() external pure override returns (uint256) {
        return 1;
    }
    
    function getRoundData(uint80 _roundId) external view override 
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (_roundId, price, lastUpdated, lastUpdated, _roundId);
    }
    
    function latestRoundData() external view override 
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        // This is where the bug could be - returning stale data without proper validation
        return (
            uint80(block.number),
            price,
            lastUpdated,
            lastUpdated,
            uint80(block.number)
        );
    }
    
    // Test functions to manipulate oracle state
    function setPrice(int256 _price) external {
        price = _price;
        lastUpdated = block.timestamp;
        isStale = false;
    }
    
    function makeStale() external {
        isStale = true;
        // Don't update lastUpdated to simulate stale data
    }
    
    function setStalenessThreshold(uint256 _threshold) external {
        stalenessThreshold = _threshold;
    }
    
    function isDataStale() public view returns (bool) {
        return block.timestamp - lastUpdated > stalenessThreshold || isStale;
    }
}

// Mock ERC4626 Vault
contract MockERC4626 is IERC4626 {
    uint256 public conversionRate = 1e18; // 1:1 conversion by default
    uint8 public decimals_ = 18;
    
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return shares * conversionRate / 1e18;
    }
    
    function decimals() external view override returns (uint8) {
        return decimals_;
    }
    
    function setConversionRate(uint256 _rate) external {
        conversionRate = _rate;
    }
}

// Simplified version of the oracle for testing
contract TestMorphoOracle {
    MockERC4626 public immutable baseVault;
    MockERC4626 public immutable quoteVault;
    MockAggregatorV3 public immutable baseFeed1;
    MockAggregatorV3 public immutable baseFeed2;
    MockAggregatorV3 public immutable quoteFeed1;
    MockAggregatorV3 public immutable quoteFeed2;
    
    uint256 public constant STALENESS_THRESHOLD = 3600; // 1 hour
    
    constructor(
        MockERC4626 _baseVault,
        MockAggregatorV3 _baseFeed1,
        MockAggregatorV3 _baseFeed2,
        MockERC4626 _quoteVault,
        MockAggregatorV3 _quoteFeed1,
        MockAggregatorV3 _quoteFeed2
    ) {
        baseVault = _baseVault;
        baseFeed1 = _baseFeed1;
        baseFeed2 = _baseFeed2;
        quoteVault = _quoteVault;
        quoteFeed1 = _quoteFeed1;
        quoteFeed2 = _quoteFeed2;
    }
    
    function getPrice() external view returns (uint256) {
        // Get base token price (using feed1 as primary, feed2 as fallback)
        (, int256 basePrice1, , uint256 baseUpdatedAt1, ) = baseFeed1.latestRoundData();
        (, int256 basePrice2, , uint256 baseUpdatedAt2, ) = baseFeed2.latestRoundData();
        
        // Get quote token price
        (, int256 quotePrice1, , uint256 quoteUpdatedAt1, ) = quoteFeed1.latestRoundData();
        (, int256 quotePrice2, , uint256 quoteUpdatedAt2, ) = quoteFeed2.latestRoundData();
        
        // This is where the vulnerability could be - no staleness checks!
        // In a real implementation, we should check:
        // require(block.timestamp - baseUpdatedAt1 <= STALENESS_THRESHOLD, "Stale base price");
        // require(block.timestamp - quoteUpdatedAt1 <= STALENESS_THRESHOLD, "Stale quote price");
        
        uint256 basePrice = basePrice1 > 0 ? uint256(basePrice1) : uint256(basePrice2);
        uint256 quotePrice = quotePrice1 > 0 ? uint256(quotePrice1) : uint256(quotePrice2);
        
        // Calculate relative price
        return (basePrice * 1e18) / quotePrice;
    }
    
    function isPriceStale() external view returns (bool) {
        (, , , uint256 baseUpdatedAt1, ) = baseFeed1.latestRoundData();
        (, , , uint256 baseUpdatedAt2, ) = baseFeed2.latestRoundData();
        (, , , uint256 quoteUpdatedAt1, ) = quoteFeed1.latestRoundData();
        (, , , uint256 quoteUpdatedAt2, ) = quoteFeed2.latestRoundData();
        
        return (block.timestamp - baseUpdatedAt1 > STALENESS_THRESHOLD) ||
               (block.timestamp - baseUpdatedAt2 > STALENESS_THRESHOLD) ||
               (block.timestamp - quoteUpdatedAt1 > STALENESS_THRESHOLD) ||
               (block.timestamp - quoteUpdatedAt2 > STALENESS_THRESHOLD);
    }
}

// Echidna Test Contract
contract EchidnaOracleTest {
    TestMorphoOracle public oracle;
    MockERC4626 public baseVault;
    MockERC4626 public quoteVault;
    MockAggregatorV3 public baseFeed1;
    MockAggregatorV3 public baseFeed2;
    MockAggregatorV3 public quoteFeed1;
    MockAggregatorV3 public quoteFeed2;
    
    // Track price history for detecting manipulation
    uint256[] public priceHistory;
    uint256 public constant MAX_PRICE_DEVIATION = 20; // 20% max deviation
    uint256 public constant MIN_REASONABLE_PRICE = 1e15; // Minimum reasonable price
    uint256 public constant MAX_REASONABLE_PRICE = 1e25; // Maximum reasonable price
    
    constructor() {
        // Initialize mock contracts
        baseVault = new MockERC4626();
        quoteVault = new MockERC4626();
        baseFeed1 = new MockAggregatorV3(2000e8, 8); // $2000 base price
        baseFeed2 = new MockAggregatorV3(2000e8, 8); // $2000 base price (backup)
        quoteFeed1 = new MockAggregatorV3(1e8, 8);   // $1 quote price  
        quoteFeed2 = new MockAggregatorV3(1e8, 8);   // $1 quote price (backup)
        
        oracle = new TestMorphoOracle(
            baseVault,
            baseFeed1,
            baseFeed2,
            quoteVault,
            quoteFeed1,
            quoteFeed2
        );
        
        // Initialize price history
        priceHistory.push(oracle.getPrice());
    }
    
    // ECHIDNA INVARIANTS
    
    // Invariant 1: Price should never be zero (unless there's a critical error)
    function echidna_price_not_zero() public view returns (bool) {
        uint256 currentPrice = oracle.getPrice();
        return currentPrice > 0;
    }
    
    // Invariant 2: Price should be within reasonable bounds
    function echidna_price_bounds() public view returns (bool) {
        uint256 currentPrice = oracle.getPrice();
        return currentPrice >= MIN_REASONABLE_PRICE && currentPrice <= MAX_REASONABLE_PRICE;
    }
    
    // Invariant 3: If oracle is stale, it should be detected
    function echidna_stale_detection() public view returns (bool) {
        // If any feed is stale according to our mock, the oracle should detect it
        bool anyFeedStale = baseFeed1.isDataStale() || baseFeed2.isDataStale() || 
                           quoteFeed1.isDataStale() || quoteFeed2.isDataStale();
        bool oracleDetectsStale = oracle.isPriceStale();
        
        // If feeds are stale, oracle should detect it
        return !anyFeedStale || oracleDetectsStale;
    }
    
    // Invariant 4: Price shouldn't change drastically without feed updates
    function echidna_price_stability() public returns (bool) {
        uint256 currentPrice = oracle.getPrice();
        
        if (priceHistory.length > 0) {
            uint256 lastPrice = priceHistory[priceHistory.length - 1];
            
            // Calculate percentage change
            uint256 priceDiff = currentPrice > lastPrice ? 
                currentPrice - lastPrice : lastPrice - currentPrice;
            uint256 percentageChange = (priceDiff * 100) / lastPrice;
            
            // Price shouldn't change more than MAX_PRICE_DEVIATION% without feed updates
            if (percentageChange > MAX_PRICE_DEVIATION) {
                // Check if feeds were actually updated
                (, , , uint256 baseUpdated1, ) = baseFeed1.latestRoundData();
                (, , , uint256 baseUpdated2, ) = baseFeed2.latestRoundData();
                (, , , uint256 quoteUpdated1, ) = quoteFeed1.latestRoundData();
                (, , , uint256 quoteUpdated2, ) = quoteFeed2.latestRoundData();
                
                // At least one feed should have been updated recently for large price changes
                bool recentUpdate = (block.timestamp - baseUpdated1 <= 300) ||
                                   (block.timestamp - baseUpdated2 <= 300) ||
                                   (block.timestamp - quoteUpdated1 <= 300) ||
                                   (block.timestamp - quoteUpdated2 <= 300);
                
                if (!recentUpdate) {
                    return false; // Price changed too much without recent updates
                }
            }
        }
        
        // Update price history
        priceHistory.push(currentPrice);
        if (priceHistory.length > 10) {
            // Keep only last 10 prices to save gas
            for (uint i = 0; i < 9; i++) {
                priceHistory[i] = priceHistory[i + 1];
            }
            priceHistory.pop();
        }
        
        return true;
    }
    
    // TEST FUNCTIONS (for Echidna to call)
    
    function updateBaseFeed1Price(int256 newPrice) public {
        // Bound the price to reasonable values
        newPrice = int256(bound(uint256(newPrice), 1e6, 1e12)); // $0.01 to $10k
        baseFeed1.setPrice(newPrice);
    }
    
    function updateQuoteFeed1Price(int256 newPrice) public {
        newPrice = int256(bound(uint256(newPrice), 1e6, 1e10)); // $0.01 to $100
        quoteFeed1.setPrice(newPrice);
    }
    
    function makeBaseFeed1Stale() public {
        baseFeed1.makeStale();
    }
    
    function makeQuoteFeed1Stale() public {
        quoteFeed1.makeStale();
    }
    
    function updateVaultRates(uint256 baseRate, uint256 quoteRate) public {
        baseRate = bound(baseRate, 1e17, 2e18); // 0.1x to 2x
        quoteRate = bound(quoteRate, 1e17, 2e18);
        baseVault.setConversionRate(baseRate);
        quoteVault.setConversionRate(quoteRate);
    }
    
    // Utility function to bound values
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
    
    // Function to advance time (simulating block.timestamp changes)
    function advanceTime(uint256 timeStep) public {
        // This would need to be implemented in the test environment
        // Echidna can simulate time passage
    }
}