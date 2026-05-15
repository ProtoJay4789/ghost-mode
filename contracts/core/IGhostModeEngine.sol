// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGhostModeEngine — Core interface for the Ghost Mode transaction engine
/// @notice Stack-agnostic privacy + risk layer for agentic transactions
interface IGhostModeEngine {
    // ── Events ─────────────────────────────────────────────────────────
    event TransactionSubmitted(
        uint256 txId,
        address agent,
        bytes32 payloadHash,
        address riskOracle,
        uint256 timestamp
    );
    event RiskAssessmentComplete(
        uint256 txId,
        RiskLevel riskLevel,
        uint256 riskScore,
        string reason
    );
    event PrivacyProcessed(
        uint256 txId,
        address agent,
        bool metadataStripped
    );
    event EngineConfigured(
        address riskOracle,
        address privacyProcessor,
        bool enforcementEnabled
    );

    // ── Types ──────────────────────────────────────────────────────────
    enum RiskLevel { Safe, Review, Block }
    enum TxStatus { Pending, PrivacyProcessed, RiskChecking, Approved, Rejected }

    // ── Structs ────────────────────────────────────────────────────────
    struct GhostTransaction {
        uint256 txId;
        address agent;
        bytes32 payloadHash;      // Hash of original transaction data
        bytes32 sanitizedHash;    // Hash after privacy processing
        RiskLevel riskLevel;
        TxStatus status;
        uint256 riskScore;        // 0-100 from Somnia LLM
        string riskReason;
        uint256 submittedAt;
        uint256 resolvedAt;
    }

    // ── Core Functions ─────────────────────────────────────────────────
    /// @notice Submit a transaction for ghost mode processing
    /// @param payload Raw transaction data from the agent
    /// @return txId The unique transaction ID for tracking
    function submitTransaction(bytes calldata payload) external returns (uint256 txId);

    /// @notice Check the status and risk assessment of a transaction
    /// @param txId Transaction ID to query
    /// @return tx The GhostTransaction record
    function getTransactionStatus(uint256 txId) external view returns (GhostTransaction memory tx);

    /// @notice Check if a transaction is approved for execution
    /// @param txId Transaction ID
    /// @return approved Whether the transaction passed all checks
    function isApproved(uint256 txId) external view returns (bool approved);

    // ── Admin Functions ────────────────────────────────────────────────
    function setRiskOracle(address _riskOracle) external;
    function setPrivacyProcessor(address _privacyProcessor) external;
    function setEnforcement(bool _enabled) external;
}
