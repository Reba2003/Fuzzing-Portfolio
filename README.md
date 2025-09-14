## Fuzzing-Portfolio
This is my fuzzing work for my portfolio

## Thought process
I'll be fuzzing a couple of smart contract to test contract behaviour and possible bugs

## Finding 1: Missing Staleness Checks in Chainlink Oracle
Severity: High

Target:(https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/ChainlinkDataFeedLib.sol#L20-L27)

Type: Logical Vulnerability

# Overview

The library ChainlinkDataFeedLib contains a critical, intentionally implemented vulnerability. The developers have explicitly chosen to omit standard security checks (staleness, bounds, round completeness) when querying Chainlink price feeds, based on the assumption that "Chainlink feed keeps its promises." This design decision violates Chainlink's own best practices and introduces severe, systemic risk into any protocol relying on this library for pricing data.

# Technical Details


The Flawed Code Pattern

The library function getPrice() makes a call to latestRoundData() but only captures the answer field, ignoring the other critical return values (updatedAt, answeredInRound).

# Why is this a bug/vulnerability?

Chainlink feeds are decentralized. A feed can become stale due to a multitude of real-world issues: a node operator going down, network congestion, a wormhole/layer-zero bridge failure for cross-chain feeds, or a malicious operator. Chainlink's own documentation recommends implementing staleness checks on-chain. Relying on promises is not a security strategy.

# Impact

- Systemic Risk: A failure of a single Chainlink feed (e.g., a mainnet feed going stale for an hour due to a bug) can now compromise the entire Morpho ecosystem and any other integrated protocols, as there are no circuit breakers.

- Complete Loss of Funds: Stale prices can lead to massive, protocol-solvency-threatening issues:

Undercollateralized Borrowing: A stale, inflated asset price allows users to borrow far more than their collateral should allow. If the price corrects, the protocol is left with bad debt.

Unjust Liquidations: A stale, deflated asset price will cause healthy positions to be liquidated, robbing users of their funds and damaging trust.

# Proof Of Concept

So I created this contract to test for stale price possibilities:
https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/EchidnaOracleTest.sol#L1-L315

And this was the output:
https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/Finding%201_1.png

https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/Finding%201_10.png

https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/Finding%201_10.png

The fuzzer proved that the assumption is invalid. It easily found paths to:

Set a feed to a stale value.

Observe that the oracle (TestMorphoOracle) had no ability to detect this (stale_detection failed).

Observe that the oracle then returned a price that was completely unreasonable (price_bounds failed) and volatile without cause (price_stability failed).

This simulated environment directly mirrors a real-world scenario where a Chainlink feed fails, proving that the protocol's security cannot be based on assumptions and promises.

# Remediation

// Add constants for security parameters
uint256 private constant STALENESS_THRESHOLD = 3600; // 1 hour
uint256 private constant MAX_PRICE = 1e25; // Maximum sane price
uint256 private constant MIN_PRICE = 1e15; // Minimum sane price

function getPrice(AggregatorV3Interface feed) internal view returns (uint256) {
    if (address(feed) == address(0)) return 1;

    (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
    
    // 1. Check for a positive answer
    require(answer > 0, ErrorsLib.NEGATIVE_OR_ZERO_ANSWER);
    
    // 2. Check for a complete round
    require(answeredInRound >= roundId, ErrorsLib.INCOMPLETE_ROUND);
    
    // 3. Check that the price is not stale
    require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, ErrorsLib.STALE_PRICE);
    
    // 4. (Optional but recommended) Check for reasonable bounds
    uint256 price = uint256(answer);
    require(price >= MIN_PRICE && price <= MAX_PRICE, ErrorsLib.PRICE_OUT_OF_BOUNDS);

    return price;
}


