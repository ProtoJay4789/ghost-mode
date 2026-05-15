import hre from "hardhat";

async function main() {
  const [deployer] = await hre.viem.getWalletClients();

  console.log("Deploying Ghost Mode contracts from:", deployer.account.address);

  // ── Deploy Privacy Processor ────────────────────────────────────────
  // PrivacyLevel.Partial = 1 (strips non-essential metadata by default)
  const privacyProcessor = await hre.viem.deployContract("PrivacyProcessor", [
    deployer.account.address, // ghostEngine (will be updated after deploy)
    1,                        // PrivacyLevel.Partial
  ]);

  console.log("PrivacyProcessor deployed to:", privacyProcessor.address);

  // ── Deploy AgentCatcherOracle ───────────────────────────────────────
  const platform = process.env.SOMNIA_PLATFORM || "0x7407cb35a17D511D1Bd32dD726ADb8D5344ECbE3";
  const depositWei = hre.viem.parseEther(process.env.SOMNIA_DEPOSIT_STT || "0.30");

  const oracle = await hre.viem.deployContract("AgentCatcherOracle", [
    platform,
    deployer.account.address, // ghostEngine (will be updated after deploy)
    depositWei,
  ]);

  console.log("AgentCatcherOracle deployed to:", oracle.address);

  // ── Deploy GhostModeEngine ──────────────────────────────────────────
  const engine = await hre.viem.deployContract("GhostModeEngine", [
    [deployer.account.address], // initial agents
    [deployer.account.address], // initial admins
  ]);

  console.log("GhostModeEngine deployed to:", engine.address);

  // ── Wire up contracts ───────────────────────────────────────────────
  console.log("\nWiring up contracts...");

  // Engine -> Oracle
  await engine.write.setRiskOracle([oracle.address]);
  console.log("  Engine risk oracle set:", oracle.address);

  // Engine -> Privacy Processor
  await engine.write.setPrivacyProcessor([privacyProcessor.address]);
  console.log("  Engine privacy processor set:", privacyProcessor.address);

  // Oracle -> Engine
  await oracle.write.setEngine([engine.address]);
  console.log("  Oracle engine set:", engine.address);

  // Privacy -> Engine
  await privacyProcessor.write.setEngine([engine.address]);
  console.log("  Privacy processor engine set:", engine.address);

  console.log("\n✅ Ghost Mode Engine deployed and configured!");
  console.log("\nAddresses:");
  console.log("  Engine:", engine.address);
  console.log("  Oracle:", oracle.address);
  console.log("  Privacy:", privacyProcessor.address);

  // Save addresses for scripts
  console.log(`\n# Add to .env:`);
  console.log(`ENGINE_ADDRESS=${engine.address}`);
  console.log(`ORACLE_ADDRESS=${oracle.address}`);
  console.log(`PRIVACY_ADDRESS=${privacyProcessor.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
