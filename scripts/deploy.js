require('dotenv').config();
const hre = require('hardhat');
const fs = require('fs');
const path = require('path');

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log('Deploying with account:', deployer.address);
  const PropertyRegistry = await hre.ethers.getContractFactory('PropertyRegistry');
  // Constructor expects an admin address -> pass deployer.address
  const registry = await PropertyRegistry.deploy(deployer.address);
  // Ethers v6: waitForDeployment instead of deployed()
  await registry.waitForDeployment();
  const address = await registry.getAddress();
  console.log('PropertyRegistry deployed at:', address);

  // Write deployment artifact for Rails auto-loading
  const outDir = path.join(__dirname, '..', 'deployments', 'localhost');
  fs.mkdirSync(outDir, { recursive: true });
  const artifact = {
    address,
    network: 'localhost',
    abi: PropertyRegistry.interface.formatJson()
  };
  fs.writeFileSync(path.join(outDir, 'PropertyRegistry.json'), JSON.stringify(artifact, null, 2));
  console.log('Saved deployment artifact to deployments/localhost/PropertyRegistry.json');

  // Optional automatic role granting
  const notaryAddress = process.env.NOTARY_ADDRESS || process.env.DEFAULT_NOTARY || '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';
  const governmentAddress = process.env.GOVERNMENT_ADDRESS || process.env.DEFAULT_GOVERNMENT || '0x90F79bf6EB2c4f870365E785982E1f101E93b906';

  // Grant NOTARY_ROLE and GOVERNMENT_ROLE if provided
  try {
    const notaryRole = await registry.NOTARY_ROLE();
    const govRole = await registry.GOVERNMENT_ROLE();
    if (notaryAddress) {
      const tx1 = await registry.grantRole(notaryRole, notaryAddress);
      await tx1.wait();
      console.log('Granted NOTARY_ROLE to', notaryAddress);
    }
    if (governmentAddress) {
      const tx2 = await registry.grantRole(govRole, governmentAddress);
      await tx2.wait();
      console.log('Granted GOVERNMENT_ROLE to', governmentAddress);
    }
  } catch (err) {
    console.warn('Role granting skipped or failed:', err.message);
  }

  console.log('Deployment complete. Roles (if addresses provided) granted.');
}

main().catch((e) => { console.error(e); process.exit(1); });
