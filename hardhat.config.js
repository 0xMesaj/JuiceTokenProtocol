/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-waffle');
// require("hardhat-gas-reporter");
module.exports = {
  solidity: {
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000
      }
    },
    compilers: [
      {
        version: "0.4.24",
        settings: { } 
      },
      {
        version: "0.5.12",
        settings: { } 
      },
      {
        version: "0.8.0",
        settings: { } 
      },
      {
        version: "0.6.12",
        settings: { } 
      },
      {
        version: "0.7.3",
        settings: { } 
      }
     
    ],
    overrides: {
      "contracts/SportsBook.sol": {
        version: "0.6.12",
        settings: { }
    }
   }
  }
};
