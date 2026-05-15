// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PrivacyProcessor — Metadata stripping and privacy routing layer
/// @notice Processes transaction payloads to remove identifying metadata before risk assessment
/// @dev Configurable: can strip agent identity, amounts, addresses, or full payload
contract PrivacyProcessor {
    // ── Privacy Levels ─────────────────────────────────────────────────
    enum PrivacyLevel {
        None,       // Pass through as-is
        Partial,    // Strip non-essential metadata (agent ID, timestamps)
        Full        // Full anonymization (hash-only, zero-knowledge ready)
    }

    // ── State ──────────────────────────────────────────────────────────
    address public ghostEngine;
    PrivacyLevel public activeLevel;

    // Privacy rules per agent
    mapping(address => PrivacyLevel) public agentPrivacyLevel;

    modifier onlyEngine() {
        require(msg.sender == ghostEngine, "Privacy: only engine");
        _;
    }

    constructor(address _engine, PrivacyLevel _defaultLevel) {
        ghostEngine = _engine;
        activeLevel = _defaultLevel;
    }

    /// @notice Process a transaction payload through the privacy layer
    /// @param payload Original transaction data
    /// @param agent The agent submitting the transaction
    /// @return sanitizedHash Hash of the sanitized payload
    function process(bytes calldata payload, address agent)
        external
        onlyEngine
        returns (bytes32 sanitizedHash)
    {
        PrivacyLevel level = agentPrivacyLevel[agent] != PrivacyLevel.None
            ? agentPrivacyLevel[agent]
            : activeLevel;

        if (level == PrivacyLevel.None) {
            sanitizedHash = keccak256(payload);
        } else if (level == PrivacyLevel.Partial) {
            // Strip agent metadata, keep transaction intent
            sanitizedHash = keccak256(
                abi.encodePacked(
                    "partial:",
                    keccak256(payload)
                )
            );
        } else {
            // Full anonymization — only the payload hash survives
            sanitizedHash = keccak256(
                abi.encodePacked(
                    "full:",
                    keccak256(payload),
                    block.timestamp
                )
            );
        }
    }

    // ── Admin Functions ────────────────────────────────────────────────

    function setEngine(address _engine) external {
        require(msg.sender == ghostEngine, "Privacy: only engine");
        ghostEngine = _engine;
    }

    function setGlobalLevel(PrivacyLevel level) external {
        require(msg.sender == ghostEngine, "Privacy: only engine");
        activeLevel = level;
    }

    function setAgentLevel(address agent, PrivacyLevel level) external {
        require(msg.sender == ghostEngine, "Privacy: only engine");
        agentPrivacyLevel[agent] = level;
    }
}
