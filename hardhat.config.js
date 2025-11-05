require('dotenv').config();
require('@nomicfoundation/hardhat-toolbox');

/**
 * Hardhat configuration
 * - Uses .env for PRIVATE_KEY, RPC_URL (testnet), ETHERSCAN_API_KEY optional
 */
module.exports = {
  solidity: {
    version: '0.8.21',
    settings: { optimizer: { enabled: true, runs: 200 } }
  },
  networks: {
    localhost: { url: 'http://127.0.0.1:8545' },
    sepolia: {
      url: process.env.RPC_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    }
  },
  etherscan: { apiKey: process.env.ETHERSCAN_API_KEY || '' }
};
