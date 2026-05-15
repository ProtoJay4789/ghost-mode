// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGhostModeEngine} from "./IGhostModeEngine.sol";

/// @title GhostModeEngine — Core transaction intercept + risk routing engine
/// @notice Stack-agnostic: works with any agent framework (Hermes, OpenCode, Claude Code, Codex)
/// @dev Integrates with Somnia Agent Platform for on-chain LLM risk scoring
contract GhostModeEngine is IGhostModeEngine {
    // ── State ──────────────────────────────────────────────────────────
    address public riskOracle;
    address public privacyProcessor;
    bool public enforcementEnabled = true;
    uint256 private _txCounter;

    mapping(uint256 => GhostTransaction) private _transactions;
    mapping(address => bool) public authorizedAgents;
    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(admins[msg.sender], "GhostMode: not admin");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedAgents[msg.sender], "GhostMode: agent not authorized");
        _;
    }

    modifier onlyRiskOracle() {
        require(msg.sender == riskOracle, "GhostMode: only risk oracle");
        _;
    }

    modifier onlyPrivacyProcessor() {
        require(msg.sender == privacyProcessor, "GhostMode: only privacy processor");
        _;
    }

    constructor(address[] memory initialAgents, address[] memory initialAdmins) {
        for (uint256 i = 0; i < initialAgents.length; i++) {
            authorizedAgents[initialAgents[i]] = true;
        }
        for (uint256 i = 0; i < initialAdmins.length; i++) {
            admins[initialAdmins[i]] = true;
        }
        admins[msg.sender] = true;
    }

    // ── Core Flow ──────────────────────────────────────────────────────

    /// @notice Submit transaction for ghost mode processing
    /// Phase 1: Privacy processing (metadata stripping)
    /// Phase 2: Risk assessment via Somnia LLM (async callback)
    function submitTransaction(bytes calldata payload)
        external
        onlyAuthorized
        returns (uint256 txId)
    {
        txId = ++_txCounter;

        _transactions[txId] = GhostTransaction({
            txId: txId,
            agent: msg.sender,
            payloadHash: keccak256(payload),
            sanitizedHash: bytes32(0),
            riskLevel: RiskLevel.Safe,
            status: TxStatus.Pending,
            riskScore: 0,
            riskReason: "",
            submittedAt: block.timestamp,
            resolvedAt: 0
        });

        emit TransactionSubmitted(
            txId,
            msg.sender,
            keccak256(payload),
            riskOracle,
            block.timestamp
        );

        // Route to privacy processor first
        if (privacyProcessor != address(0)) {
            _processPrivacy(txId, payload);
        }

        // Then route to risk oracle
        if (riskOracle != address(0)) {
            _requestRiskAssessment(txId, payload);
        } else {
            // No risk oracle configured — auto-approve if enforcement off
            if (!enforcementEnabled) {
                _transactions[txId].status = TxStatus.Approved;
                _transactions[txId].resolvedAt = block.timestamp;
            }
        }
    }

    // ── Privacy Processing ─────────────────────────────────────────────

    function _processPrivacy(uint256 txId, bytes memory payload) internal {
        _transactions[txId].status = TxStatus.PrivacyProcessed;

        // Privacy processor strips metadata and returns sanitized hash
        // In production: IPrivacyProcessor(privacyProcessor).process(payload)
        bytes32 sanitizedHash = keccak256(abi.encodePacked("sanitized:", payload));
        _transactions[txId].sanitizedHash = sanitizedHash;

        emit PrivacyProcessed(txId, msg.sender, true);
    }

    // ── Risk Assessment ────────────────────────────────────────────────

    function _requestRiskAssessment(uint256 txId, bytes memory payload) internal {
        _transactions[txId].status = TxStatus.RiskChecking;

        // Risk oracle makes async Somnia LLM call
        // In production: IAgentCatcher(riskOracle).requestAssessment(txId, payload)
        emit RiskAssessmentRequested(txId, payload);
    }

    // ── Callback from Risk Oracle ──────────────────────────────────────

    /// @notice Called by risk oracle when Somnia LLM assessment completes
    function receiveRiskAssessment(
        uint256 txId,
        RiskLevel riskLevel,
        uint256 riskScore,
        string calldata reason
    ) external onlyRiskOracle {
        require(_transactions[txId].txId != 0, "GhostMode: invalid txId");

        _transactions[txId].riskLevel = riskLevel;
        _transactions[txId].riskScore = riskScore;
        _transactions[txId].riskReason = reason;
        _transactions[txId].resolvedAt = block.timestamp;

        // Apply enforcement rules
        if (enforcementEnabled) {
            if (riskLevel == RiskLevel.Block) {
                _transactions[txId].status = TxStatus.Rejected;
            } else if (riskLevel == RiskLevel.Review) {
                // Review status — requires admin override or auto-approve after timeout
                _transactions[txId].status = TxStatus.Rejected; // Default to reject on review
            } else {
                _transactions[txId].status = TxStatus.Approved;
            }
        } else {
            // Enforcement off — log but don't block
            _transactions[txId].status = TxStatus.Approved;
        }

        emit RiskAssessmentComplete(txId, riskLevel, riskScore, reason);
    }

    // ── View Functions ─────────────────────────────────────────────────

    function getTransactionStatus(uint256 txId)
        external
        view
        returns (GhostTransaction memory tx)
    {
        tx = _transactions[txId];
    }

    function isApproved(uint256 txId) external view returns (bool approved) {
        return _transactions[txId].status == TxStatus.Approved;
    }

    // ── Admin Functions ────────────────────────────────────────────────

    function setRiskOracle(address _riskOracle) external onlyAdmin {
        riskOracle = _riskOracle;
        emit EngineConfigured(_riskOracle, privacyProcessor, enforcementEnabled);
    }

    function setPrivacyProcessor(address _privacyProcessor) external onlyAdmin {
        privacyProcessor = _privacyProcessor;
        emit EngineConfigured(riskOracle, _privacyProcessor, enforcementEnabled);
    }

    function setEnforcement(bool _enabled) external onlyAdmin {
        enforcementEnabled = _enabled;
        emit EngineConfigured(riskOracle, privacyProcessor, _enabled);
    }

    function addAgent(address agent) external onlyAdmin {
        authorizedAgents[agent] = true;
    }

    function removeAgent(address agent) external onlyAdmin {
        authorizedAgents[agent] = false;
    }

    // ── Events (additional) ────────────────────────────────────────────
    event RiskAssessmentRequested(uint256 txId, bytes payload);
}
