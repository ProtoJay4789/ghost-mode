import { expect } from "chai";
import hre from "hardhat";

describe("GhostModeEngine", function () {
  let engine: any;
  let oracle: any;
  let privacy: any;
  let owner: any;
  let agent: any;

  beforeEach(async () => {
    [owner, agent] = await hre.viem.getWalletClients();

    // Deploy Privacy Processor
    privacy = await hre.viem.deployContract("PrivacyProcessor", [
      owner.account.address,
      1, // PrivacyLevel.Partial
    ]);

    // Deploy Oracle (using mock platform for testing)
    oracle = await hre.viem.deployContract("AgentCatcherOracle", [
      owner.account.address, // mock platform
      owner.account.address, // engine
      hre.viem.parseEther("0.30"),
    ]);

    // Deploy Engine
    engine = await hre.viem.deployContract("GhostModeEngine", [
      [agent.account.address],
      [owner.account.address],
    ]);

    // Wire up
    await engine.write.setRiskOracle([oracle.address]);
    await engine.write.setPrivacyProcessor([privacy.address]);
  });

  describe("Deployment", () => {
    it("Should set the right admin", async () => {
      expect(await engine.read.admins([owner.account.address])).to.equal(true);
    });

    it("Should authorize the agent", async () => {
      expect(await engine.read.authorizedAgents([agent.account.address])).to.equal(true);
    });
  });

  describe("Transaction Submission", () => {
    it("Should allow authorized agents to submit", async () => {
      const payload = hre.viem.encodeAbiParameters(
        [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }],
        ["0x1234567890123456789012345678901234567890", hre.viem.parseEther("1")]
      );

      const tx = await agent.writeContract({
        address: engine.address,
        abi: engine.abi,
        functionName: "submitTransaction",
        args: [payload],
      });

      expect(tx).to.not.be.undefined;
    });

    it("Should reject unauthorized agents", async () => {
      const [unauthorized] = await hre.viem.getWalletClients();
      const payload = hre.viem.encodeAbiParameters(
        [{ name: "to", type: "address" }],
        ["0x1234567890123456789012345678901234567890"]
      );

      try {
        await unauthorized.writeContract({
          address: engine.address,
          abi: engine.abi,
          functionName: "submitTransaction",
          args: [payload],
        });
        expect.fail("Should have reverted");
      } catch (err: any) {
        expect(err.message).to.include("not authorized");
      }
    });
  });

  describe("Risk Assessment", () => {
    it("Should receive risk assessment from oracle", async () => {
      // Submit a transaction
      const payload = hre.viem.encodeAbiParameters(
        [{ name: "data", type: "bytes" }],
        ["0xdeadbeef"]
      );

      await agent.writeContract({
        address: engine.address,
        abi: engine.abi,
        functionName: "submitTransaction",
        args: [payload],
      });

      const txId = 1n;

      // Simulate oracle callback
      await oracle.write.receiveRiskAssessment([
        txId,
        0, // RiskLevel.Safe
        15n,
        "Transaction passed all risk checks",
      ]);

      const tx = await engine.read.getTransactionStatus([txId]);
      expect(tx[4]).to.equal(3n); // TxStatus.Approved
    });

    it("Should block high-risk transactions when enforcement enabled", async () => {
      const txId = 1n;

      await oracle.write.receiveRiskAssessment([
        txId,
        2, // RiskLevel.Block
        85n,
        "Transaction blocked by risk assessment",
      ]);

      const tx = await engine.read.getTransactionStatus([txId]);
      expect(tx[4]).to.equal(4n); // TxStatus.Rejected
    });
  });

  describe("Admin Controls", () => {
    it("Should allow admin to toggle enforcement", async () => {
      await engine.write.setEnforcement([false]);
      expect(await engine.read.enforcementEnabled()).to.equal(false);
    });

    it("Should not allow non-admin to toggle enforcement", async () => {
      try {
        await agent.writeContract({
          address: engine.address,
          abi: engine.abi,
          functionName: "setEnforcement",
          args: [false],
        });
        expect.fail("Should have reverted");
      } catch (err: any) {
        expect(err.message).to.include("not admin");
      }
    });
  });
});
