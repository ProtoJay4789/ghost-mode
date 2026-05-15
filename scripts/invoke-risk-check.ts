import hre from "hardhat";

const ENGINE_ADDRESS = process.env.ENGINE_ADDRESS as `0x${string}`;
const POLL_INTERVAL = 3000;
const TIMEOUT = 180_000; // 3 minutes for Somnia LLM callback

async function main() {
  if (!ENGINE_ADDRESS) {
    console.error("ENGINE_ADDRESS not set. Run deploy first and add to .env");
    process.exit(1);
  }

  const engine = await hre.viem.getContractAt("GhostModeEngine", ENGINE_ADDRESS);
  const publicClient = await hre.viem.getPublicClient();

  // Create a sample transaction payload
  const payload = hre.viem.encodeAbiParameters(
    [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
    [
      "0x1234567890123456789012345678901234567890",
      hre.viem.parseEther("0.001"),
      "0x",
    ]
  );

  console.log("Submitting transaction for risk assessment...");

  const txHash = await engine.write.submitTransaction([payload]);
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  const fromBlock = receipt.blockNumber;

  console.log("Transaction submitted in block:", fromBlock);

  // Extract txId from TransactionSubmitted event
  const events = await engine.getEvents.TransactionSubmitted({}, { fromBlock });
  if (events.length === 0) {
    console.error("No TransactionSubmitted event found");
    process.exit(1);
  }

  const txId = events[0].args.txId!;
  console.log("Transaction ID:", txId.toString());

  // Poll for risk assessment completion
  console.log("Waiting for Somnia LLM risk assessment...");
  const startTime = Date.now();

  while (Date.now() - startTime < TIMEOUT) {
    // Check for RiskAssessmentComplete event
    const riskEvents = await engine.getEvents.RiskAssessmentComplete(
      { txId },
      { fromBlock }
    );

    if (riskEvents.length > 0) {
      const risk = riskEvents[0].args;
      console.log("\n✅ Risk Assessment Complete!");
      console.log("  Risk Level:", ["Safe", "Review", "Block"][risk.riskLevel!]);
      console.log("  Risk Score:", risk.riskScore!.toString());
      console.log("  Reason:", risk.reason);
      process.exit(0);
    }

    // Check for failures
    const status = await engine.read.getTransactionStatus([txId]);
    if (status[4] === 3n) { // TxStatus.Rejected
      console.log("\n❌ Transaction rejected");
      console.log("  Status: Rejected");
      process.exit(1);
    }
    if (status[4] === 4n) { // TxStatus.Approved
      console.log("\n✅ Transaction approved");
      console.log("  Status: Approved");
      process.exit(0);
    }

    await new Promise((r) => setTimeout(r, POLL_INTERVAL));
    process.stdout.write(".");
  }

  console.log("\n⏱️ Timeout waiting for risk assessment");
  process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
