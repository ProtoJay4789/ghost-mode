---
name: ghost-mode
description: "Ghost Mode — privacy-preserving, risk-screened transaction execution for agentic workflows. Intercepts agent transactions, strips metadata, and runs Somnia LLM risk scoring before execution."
version: 0.1.0
author: Gentech
---

# Ghost Mode — Hermes Skill Adapter

## When to Use This Skill

- An agent needs to execute a transaction with privacy guarantees
- You want pre-execution risk screening via Somnia's LLM risk oracle
- Building agent commerce flows where transactions must be vetted before settlement
- Implementing the "Agent Catcher" safety filter layer

## Architecture

```
Agent → GhostModeEngine → PrivacyProcessor → AgentCatcherOracle → Somnia LLM → Approve/Block
```

## Setup

```bash
# Ensure contracts are deployed
export ENGINE_ADDRESS=0x...    # GhostModeEngine address
export ORACLE_ADDRESS=0x...    # AgentCatcherOracle address
export PRIVACY_ADDRESS=0x...   # PrivacyProcessor address
export SOMNIA_DEPOSIT_STT=0.30 # STT for LLM calls
```

## Usage

### Submit a Transaction Through Ghost Mode

```python
from web3 import Web3
from eth_account import Account
import json

# Contract ABIs
with open("artifacts/contracts/core/GhostModeEngine.sol/GhostModeEngine.json") as f:
    engine_abi = json.load(f)["abi"]

ENGINE_ADDRESS = "0x..."  # Deployed address
w3 = Web3(Web3.HTTPProvider("https://api.infra.testnet.somnia.network"))
account = Account.from_key(os.environ["PRIVATE_KEY"])

engine = w3.eth.contract(address=ENGINE_ADDRESS, abi=engine_abi)

# Encode transaction payload
payload = engine.encodeABI(
    fn_name="submitTransaction",
    args=[your_transaction_data]
)

# Submit
tx = engine.functions.submitTransaction(your_transaction_data).buildTransaction({
    "from": account.address,
    "nonce": w3.eth.get_transaction_count(account.address),
    "gas": 500000,
})
signed = account.sign_transaction(tx)
tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

# Get txId from event
tx_id = engine.events.TransactionSubmitted().processReceipt(receipt)[0]["args"]["txId"]
```

### Check Transaction Status

```python
status = engine.functions.getTransactionStatus(tx_id).call()
# Returns: (txId, agent, payloadHash, sanitizedHash, riskLevel, status, riskScore, riskReason, submittedAt, resolvedAt)
```

## Risk Levels

| Level | Score | Behavior |
|-------|-------|----------|
| Safe | 0-30 | Auto-approved |
| Review | 31-70 | Flagged for manual review |
| Block | 71-100 | Rejected when enforcement enabled |

## Transaction Statuses

| Status | Value | Meaning |
|--------|-------|---------|
| Pending | 0 | Awaiting processing |
| PrivacyProcessed | 1 | Metadata stripped |
| RiskChecking | 2 | Awaiting Somnia LLM assessment |
| Approved | 3 | Cleared for execution |
| Rejected | 4 | Blocked by risk assessment |

## Privacy Levels

- **None**: Pass through as-is (default for trusted agents)
- **Partial**: Strip agent identity and timestamps, keep transaction intent
- **Full**: Full anonymization — hash-only, zero-knowledge ready

## Configuration

### Add/Remove Authorized Agents

```python
engine.functions.addAgent(new_agent_address).transact()
engine.functions.removeAgent(agent_address).transact()
```

### Toggle Enforcement

```python
# Enable: block transactions that fail risk checks
engine.functions.setEnforcement(True).transact()

# Disable: log risk assessments but don't block
engine.functions.setEnforcement(False).transact()
```

## Integration with Other Adapters

| Adapter | Format | Location |
|---------|--------|----------|
| Hermes | This skill | `.hermes/skills/ghost-mode/` |
| OpenCode | Plugin format | `adapters/opencode/` |
| Claude Code | MCP server | `adapters/claude-code/` |
| Codex | CLI wrapper | `adapters/codex/` |

## Pitfalls

- **Somnia LLM timeout**: Risk assessments take 10-60 seconds. Set invoke script timeout to at least 180 seconds.
- **Insufficient deposit**: LLM agents may need 0.30 STT minimum. If you get `insufficient_budget`, increase the deposit.
- **Enforcement mode**: When enforcement is enabled, Review-level transactions are rejected by default. Use disable mode for logging-only.
- **Platform address**: Verify you're using the correct Somnia platform contract for your network (testnet vs dev).
