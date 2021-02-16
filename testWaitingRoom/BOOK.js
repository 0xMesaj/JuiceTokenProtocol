const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");

describe('BOOK Token contract', () => {
    let BOOK, BOOKtoken, TransferPortal, owner, vault, addr1, addr2;
    beforeEach(async () => {
        BOOK = await ethers.getContractFactory('BookToken');
        BOOKtoken = await BOOK.deploy("BOOK Token","BOOK");

        TransferPortal = await ethers.getContractFactory('TransferPortal');        
        portal = await TransferPortal.deploy(BOOKtoken.address);

        await BOOKtoken.setTransferPortal(portal.address);
        [owner, vault, addr1, addr2, _] = await ethers.getSigners();

        await portal.connect(owner).setParameters(owner.address, vault.address, 100, 10);
    });

    describe('Deployment', () => {
        it('Should set the right owner', async () => {
            expect(await BOOKtoken.owner()).to.equal(owner.address);
        }); 

        it('Should set the right transfer portal', async () => {
            await portal.connect(owner).setParameters(vault.address, BOOKtoken.address, 100, 10);
            expect(await BOOKtoken.transferPortal()).to.equal(portal.address);
        }); 

        it('Should assign the total supply of tokens to the owner', async () => {
            const ownerBalance = await BOOKtoken.balanceOf(owner.address);
            expect(await BOOKtoken.totalSupply()).to.equal(ownerBalance);
        });
    });

    describe('Transactions', () => {
        it('Should transfer tokens between accounts', async () => {

            await BOOKtoken.transfer(addr1.address, 1000);

            const addr1Balance = await BOOKtoken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(1000*0.989);

            const vaultBalance = await BOOKtoken.balanceOf(vault.address)
            console.log("VAULT BALANCE="+vaultBalance)
            // const devBalance = await BOOKtoken.balanceOf(owner.address)
            // console.log("DEV BALANCE="+devBalance)


            // await BOOKtoken.connect(addr1).transfer(addr2.address, 49);
            // const addr2Balance = await BOOKtoken.balanceOf(addr2.address);
            // expect(addr2Balance).to.equal(49);
        });

        it('Should fail if sender doesnt have enough tokens', async () => {
            const initialOwnerBalance = await BOOKtoken.balanceOf(owner.address);
            await expect( BOOKtoken.connect(addr1).transfer(owner.address, 1) )
                .to.be
                .revertedWith('ERC20: transfer amount exceeds balance');
            expect(await BOOKtoken.balanceOf(owner.address))
                .to.equal(initialOwnerBalance)
        });

        it('Should update balance after transfers', async () => {
            const initialOwnerBalance = await BOOKtoken.balanceOf(owner.address);

            await BOOKtoken.transfer(addr1.address, 100);
            await BOOKtoken.transfer(addr2.address, 50);

            const finalOwnerBalance = await BOOKtoken.balanceOf(owner.address);
            expect(finalOwnerBalance).to.equal(initialOwnerBalance - 150);

            const addr1Balance = await BOOKtoken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(99);

            const addr2Balance = await BOOKtoken.balanceOf(addr2.address);
            expect(addr2Balance).to.equal(50);
        })
    })

    
    

  
});