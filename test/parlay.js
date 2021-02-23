const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");

// Use the TestResolve Smart Contract to test Logic of wager resolution, including edge cases

describe('Test Parlay Resolutions', () => {
    let  owner, addr1, addr2;
    beforeEach(async () => {
        sbFactory = await ethers.getContractFactory('TestParlay');
        sportsBook = await sbFactory.deploy();
        [owner, addr1, addr2, _] = await ethers.getSigners();
    });

    describe('Deployment', () => {
        it('Test', async () => {0x3139352c3335322c3138320000000000
            // await sportsBook.connect(owner).resolveParlay('0x2d3131342c2d3131330000000000000000000000000000000000000000000000')
            await sportsBook.connect(owner).resolveParlay('0x3139352c3335322c313832000000000000000000000000000000000000000000')
            var ans = await sportsBook.ans()
            console.log((parseInt(ans._hex,16)))

            // expect((parseInt(ans._hex,16))).to.equal(1);

        })

    });

 

});