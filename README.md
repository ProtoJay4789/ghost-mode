# Ghost Mode Engine

**Stack-agnostic privacy + risk layer for agentic transactions.**

Built on Somnia's AI Agent Platform for on-chain LLM risk scoring.

## Architecture

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────────┐     ┌──────────────┐
│   Agent      │────►│  GhostModeEngine  │────►│  PrivacyProcessor   │────►│   Metadata   │
│ (any stack)  │     │  (Core Router)    │     │  (Strips Identifiers)│     │   Stripped   │
└──────────────┘     └────────┬──────────┘     └─────────────────────┘     └──────────────┘
                              │
                              ▼
                     ┌─────────────────────┐     ┌─────────────────────┐
                     │ AgentCatcherOracle  │────►│  Somnia LLM Agent   │
                     │ (Risk Assessment)   │     │  (On-chain Scoring) │
                     └────────┬────────────┘     └─────────────────────┘
                              │
                              ▼
                     ┌─────────────────────┐
                     │ Safe / Review / Block│
                     │   (0-100 Score)     │
                     └─────────────────────┘
```

## Core Engine (Stack-Agnostic)

- **Transaction intercept**: All agent transactions route through the engine
- **Privacy layer**: Configurable metadata stripping (None / Partial / Full)
- **Risk check API**: Somnia "Agent Catcher" LLM scoring with constrained output
- **Config-driven rules**: Admin-controlled enforcement, agent authorization, risk thresholds

## Adapters

| Adapter | Format | Status |
|---------|--------|--------|
| **Hermes** | Skill (`.hermes/skills/ghost-mode/`) | ✅ Built |
| **OpenCode** | Plugin format | 🚧 Planned |
| **Claude Code** | MCP server | 🚧 Planned |
| **Codex** | CLI wrapper | 🚧 Planned |

## Quick Start

```bash
# Install dependencies
npm install

# Configure
cp .env.example .env
# Add PRIVATE_KEY to .env

# Compile
npm run compile

# Deploy to Somnia testnet
npm run deploy:engine
npm run deploy:oracle

# Test risk assessment
npm run invoke:risk
```

## Contracts

| Contract | Purpose |
|----------|---------|
| `GhostModeEngine` | Core router — transaction intercept, status tracking, enforcement |
| `AgentCatcherOracle` | Somnia LLM risk scoring — async callback pattern |
| `PrivacyProcessor` | Metadata stripping — configurable privacy levels |

## Network

- **Somnia Testnet**: Chain ID 50312
- **RPC**: `https://api.infra.testnet.somnia.network`
- **Explorer**: https://shannon-explorer.somnia.network
- **Faucet**: https://agents.testnet.somnia.network

## Risk Levels

| Level | Score | Behavior |
|-------|-------|----------|
| Safe | 0-30 | Auto-approved |
| Review | 31-70 | Flagged for manual review |
| Block | 71-100 | Rejected when enforcement enabled |

## License

MIT
