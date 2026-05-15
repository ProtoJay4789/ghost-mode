// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGhostModeEngine} from "../core/IGhostModeEngine.sol";

/// @title AgentCatcherOracle — Somnia LLM-powered risk assessment for agentic transactions
/// @notice Uses Somnia's LLM Inference agent to score transaction risk on-chain
/// @dev Implements the "Agent Catcher" risk layer for the Ghost Mode engine
contract AgentCatcherOracle {
    // ── Somnia Platform ────────────────────────────────────────────────
    // Testnet: 0x7407cb35a17D511D1Bd32dD726ADb8D5344ECbE3
    // Dev:     0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
    address public immutable SOMNIA_PLATFORM;

    // LLM Inference Agent ID
    uint256 public constant LLM_AGENT_ID = 12847293847561029384;

    // ── State ──────────────────────────────────────────────────────────
    address public ghostEngine;
    uint256 public depositAmount;

    // Track pending requests: requestId -> txId
    mapping(uint256 => uint256) public requestToTxId;
    mapping(uint256 => bool) public processedRequests;

    // Risk assessment rules (config-driven)
    struct RiskRule {
        string category;
        bool enabled;
        uint256 weight;  // 0-100
    }

    mapping(string => RiskRule) public rules;
    string[] public ruleCategories;

    modifier onlyEngine() {
        require(msg.sender == ghostEngine, "Oracle: only engine");
        _;
    }

    modifier onlyPlatform() {
        require(msg.sender == SOMNIA_PLATFORM, "Oracle: only platform");
        _;
    }

    constructor(
        address _platform,
        address _engine,
        uint256 _depositAmount
    ) {
        SOMNIA_PLATFORM = _platform;
        ghostEngine = _engine;
        depositAmount = _depositAmount;

        // Default risk rules
        _addRule("transaction_value", true, 25);
        _addRule("recipient_reputation", true, 20);
        _addRule("token_risk_profile", true, 20);
        _addRule("agent_behavior_pattern", true, 15);
        _addRule("network_conditions", true, 10);
        _addRule("privacy_compliance", true, 10);
    }

    function _addRule(string memory category, bool enabled, uint256 weight) internal {
        rules[category] = RiskRule(category, enabled, weight);
        ruleCategories.push(category);
    }

    // ── Risk Assessment Request ────────────────────────────────────────

    /// @notice Request risk assessment from Somnia LLM
    /// Called by GhostModeEngine when a transaction needs scoring
    function requestAssessment(
        uint256 txId,
        bytes memory payload
    ) external onlyEngine {
        // Build LLM prompt for risk analysis
        string memory prompt = _buildRiskPrompt(txId, payload);
        string memory systemPrompt = "You are a DeFi security analyst evaluating agent transaction risk. Return only one: safe, review, or block.";

        // Constrained output — LLM must return one of these values
        string[] memory allowedValues = new string[](3);
        allowedValues[0] = "safe";
        allowedValues[1] = "review";
        allowedValues[2] = "block";

        // Encode payload for Somnia LLM agent
        bytes memory llmPayload = abi.encodeWithSelector(
            bytes4(keccak256("inferString(string,string,bool,string[])")),
            prompt,
            systemPrompt,
            false,           // chainOfThought (false for faster responses)
            allowedValues
        );

        // Create request on Somnia platform
        uint256 requestId = ISomniaAgents(SOMNIA_PLATFORM).createRequest{value: depositAmount}(
            LLM_AGENT_ID,
            address(this),
            this.handleRiskResult.selector,
            llmPayload
        );

        requestToTxId[requestId] = txId;
    }

    // ── Somnia Callback ────────────────────────────────────────────────

    /// @notice Callback from Somnia platform with LLM risk assessment
    function handleRiskResult(
        uint256 requestId,
        Response[] memory responses,
        ResponseStatus status,
        Request memory /* request */
    ) external onlyPlatform {
        require(!processedRequests[requestId], "Oracle: already processed");
        processedRequests[requestId] = true;

        uint256 txId = requestToTxId[requestId];
        require(txId != 0, "Oracle: unknown request");

        if (status == ResponseStatus.Success && responses.length > 0) {
            string memory result = abi.decode(responses[0].result, (string));

            (IGhostModeEngine.RiskLevel riskLevel, uint256 score) = _parseResult(result);
            string memory reason = _generateReason(result, txId);

            // Report back to GhostModeEngine
            IGhostModeEngine(ghostEngine).receiveRiskAssessment(
                txId,
                riskLevel,
                score,
                reason
            );
        } else {
            // Failed request — default to review for safety
            IGhostModeEngine(ghostEngine).receiveRiskAssessment(
                txId,
                IGhostModeEngine.RiskLevel.Review,
                50,
                "Risk assessment failed — manual review required"
            );
        }
    }

    // ── Internal Helpers ───────────────────────────────────────────────

    function _buildRiskPrompt(uint256 txId, bytes memory payload)
        internal
        view
        returns (string memory)
    {
        // Build a structured prompt for the LLM risk assessor
        // In production, this would include actual transaction metadata
        return string.concat(
            "Assess transaction risk for txId ",
            uint256ToString(txId),
            ". Consider: transaction value, recipient reputation, token risk profile, ",
            "agent behavior patterns, network conditions, and privacy compliance. ",
            "Return: safe, review, or block."
        );
    }

    function _parseResult(string memory result)
        internal
        pure
        returns (IGhostModeEngine.RiskLevel, uint256)
    {
        if (keccak256(bytes(result)) == keccak256(bytes("safe"))) {
            return (IGhostModeEngine.RiskLevel.Safe, 15);
        } else if (keccak256(bytes(result)) == keccak256(bytes("block"))) {
            return (IGhostModeEngine.RiskLevel.Block, 85);
        } else {
            return (IGhostModeEngine.RiskLevel.Review, 50);
        }
    }

    function _generateReason(string memory result, uint256 txId)
        internal
        view
        returns (string memory)
    {
        if (keccak256(bytes(result)) == keccak256(bytes("safe"))) {
            return "Transaction passed all risk checks";
        } else if (keccak256(bytes(result)) == keccak256(bytes("block"))) {
            return "Transaction blocked by risk assessment";
        } else {
            return "Transaction flagged for manual review";
        }
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ── Admin Functions ────────────────────────────────────────────────

    function setEngine(address _engine) external {
        require(msg.sender == ghostEngine || msg.sender == tx.origin, "Oracle: unauthorized");
        ghostEngine = _engine;
    }

    function updateDeposit(uint256 _amount) external {
        require(msg.sender == tx.origin, "Oracle: unauthorized");
        depositAmount = _amount;
    }

    function updateRule(string memory category, bool enabled, uint256 weight) external {
        require(msg.sender == tx.origin, "Oracle: unauthorized");
        rules[category] = RiskRule(category, enabled, weight);
    }

    function getRequiredDeposit() external view returns (uint256) {
        return depositAmount;
    }
}

// ── Somnia Interfaces (inlined for portability) ────────────────────────

interface ISomniaAgents {
    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    function getRequestDeposit() external view returns (uint256);
}

struct Response {
    bytes result;
}

enum ResponseStatus {
    Success,
    Failed
}

struct Request {
    uint256 requestId;
    uint256 agentId;
    address requester;
    address callbackAddress;
    bytes4 callbackSelector;
    bytes payload;
    uint256 deposit;
    uint256 timestamp;
}
