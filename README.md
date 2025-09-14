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
(https://github.com/Reba2003/Fuzzing-Portfolio/blob/main/ChainlinkDataFeedLib.sol#L20-L27)

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



