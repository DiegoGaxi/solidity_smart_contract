const { expect } = require('chai');
const { ethers } = require('hardhat');

// Updated for ethers v6 (no .deployed(); use waitForDeployment(), ethers.keccak256/ toUtf8Bytes)
describe('PropertyRegistry', function () {
  let registry, seller, buyer, notary, gov;

  beforeEach(async () => {
    [seller, buyer, notary, gov] = await ethers.getSigners();
    const PropertyRegistry = await ethers.getContractFactory('PropertyRegistry');
    registry = await PropertyRegistry.deploy(seller.address);
    await registry.waitForDeployment();
    const NOTARY_ROLE = ethers.keccak256(ethers.toUtf8Bytes('NOTARY_ROLE'));
    const GOVERNMENT_ROLE = ethers.keccak256(ethers.toUtf8Bytes('GOVERNMENT_ROLE'));
    await registry.grantRole(NOTARY_ROLE, notary.address);
    await registry.grantRole(GOVERNMENT_ROLE, gov.address);
  });

  it('full approval flow', async () => {
    const docHash = ethers.keccak256(ethers.toUtf8Bytes('fileCID'));
    const tx = await registry.connect(seller).registerProperty(docHash, buyer.address, notary.address);
    const receipt = await tx.wait();

    // Parse logs to extract PropertyRegistered event
    const parsedLogs = receipt.logs.map(log => {
      try { return registry.interface.parseLog(log); } catch { return null; }
    }).filter(Boolean);
    const regEvent = parsedLogs.find(pl => pl.name === 'PropertyRegistered');
    expect(regEvent, 'PropertyRegistered event not found').to.exist;
    const id = regEvent.args.id;

    await registry.connect(notary).notaryApprove(id);
    await registry.connect(buyer).buyerApprove(id);
    await registry.connect(gov).governmentSeal(id);
    const p = await registry.getProperty(id);
    expect(p.governmentSealed).to.equal(true);
  });
});
