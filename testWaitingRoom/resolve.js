const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");

// Use the TestResolve Smart Contract to test Logic of wager resolution used in Sports Book,
// including edge cases

describe('Test Wager Resolutions', () => {
    let  SportsBook, owner, addr1, addr2;
    beforeEach(async () => {
        sbFactory = await ethers.getContractFactory('TestResolve');
        sportsBook = await sbFactory.deploy();
        [owner, addr1, addr2, _] = await ethers.getSigners();
    });

    describe('Deployment', () => {
        it('Test Home Spread', async () => {
            await sportsBook.connect(owner).computeResult('122','120',0,-15)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('122','120',0,-25)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','120',0,-20)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);

            await sportsBook.connect(owner).computeResult('120','122',0,25)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('120','122',0,15)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
        })
        it('Test Away Spread', async () => {
            await sportsBook.connect(owner).computeResult('122','120',1,25)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('122','120',1,15)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','120',1,20)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);

            await sportsBook.connect(owner).computeResult('120','122',1,-15)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('120','122',1,-25)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
        })
        it('Test Over', async () => {
            await sportsBook.connect(owner).computeResult('122','120',2,2415)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('122','120',2,2425)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','120',2,2420)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);
        })
        it('Test Under', async () => {
            await sportsBook.connect(owner).computeResult('122','120',3,2425)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('122','120',3,2415)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','120',3,2420)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);
        })
        it('Test Home ML', async () => {
            await sportsBook.connect(owner).computeResult('122','120',4,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('120','122',4,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','122',4,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);
        })
        it('Test Away ML', async () => {
            await sportsBook.connect(owner).computeResult('120','122',5,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(1);
            await sportsBook.connect(owner).computeResult('122','120',5,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(0);
            await sportsBook.connect(owner).computeResult('122','122',5,0)
            var ans = await sportsBook.win()
            expect((parseInt(ans._hex,16))).to.equal(2);
        })

    });

 

});