const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");


describe('Wdai contract', () => {
    let DAI, DAItoken, owner, addr1, addr2;
    let wDAI, wDAItoken;
    beforeEach(async () => {
        DAI = await ethers.getContractFactory('Dai');
        wDAI = await ethers.getContractFactory('WDAI');
        DAItoken = await DAI.deploy();
        wDAItoken = await wDAI.deploy(DAItoken.address, "wDAI", "wDAI");
        [owner, addr1, addr2, _] = await ethers.getSigners();

    });

    describe('Deployment', () => {
        it('Should have DAI as wrapped token', async () => {
            expect(await wDAItoken.wrappedToken()).to.equal(DAItoken.address);
        })

        it('Should assign the total supply of tokens to the owner', async () => {
            const ownerBalance = await DAItoken.balanceOf(owner.address);
            expect(await DAItoken.totalSupply()).to.equal(ownerBalance);
        });
    });

    describe('Wrapping/Unwrapping wDAI Test', () => {
        it('Should wrap DAI and receive back wDAI', async () => {
            await DAItoken.connect(owner).mint(owner.address, 20000);
            
            await DAItoken.transfer(addr1.address, 5000);
            await DAItoken.connect(addr1).approve(wDAItoken.address,constants.MaxUint256);
            const addr1Balance = await DAItoken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(5000);

            await wDAItoken.connect(addr1).deposit(50);
            const addr1WDAIBalance = await wDAItoken.balanceOf(addr1.address);
            const bal = await DAItoken.balanceOf(wDAItoken.address);
            expect(addr1WDAIBalance).to.equal(50);
            expect(bal).to.equal(50);
            
        });


        it('Should unwrap WDAI and receive back DAI', async () => {
            await DAItoken.connect(owner).mint(owner.address, 20000);
            
            await DAItoken.transfer(addr1.address, 5000);
            await DAItoken.connect(addr1).approve(wDAItoken.address,constants.MaxUint256);
            const addr1Balance = await DAItoken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(5000);

            await wDAItoken.connect(addr1).deposit(50);
            const addr1WDAIBalance = await wDAItoken.balanceOf(addr1.address);
            const bal = await DAItoken.balanceOf(wDAItoken.address);
            expect(addr1WDAIBalance).to.equal(50);
            expect(bal).to.equal(50);

            await wDAItoken.connect(addr1).withdraw(50);

            const addr1DAIBalance = await DAItoken.balanceOf(addr1.address);

            expect(addr1DAIBalance).to.equal(5000);
        });

    });

});