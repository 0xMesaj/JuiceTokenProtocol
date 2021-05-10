const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");

describe('Juice Token contract', () => {
    let JUICE, JuiceToken, TransferPortal, owner, vault, addr1, addr2;
    beforeEach(async () => {
        JUICE = await ethers.getContractFactory('JuiceToken');
        JuiceToken = await JUICE.deploy("Juice Token","JCE");

        TransferPortal = await ethers.getContractFactory('TransferPortal');        
        portal = await TransferPortal.deploy(JuiceToken.address);

        await JuiceToken.setTransferPortal(portal.address);
        [owner, vault, addr1, addr2, _] = await ethers.getSigners();

        await portal.connect(owner).setParameters(owner.address, vault.address, 100, 10);
    });

    describe('Deployment', () => {
        it('Should set the right owner', async () => {
            expect(await JuiceToken.owner()).to.equal(owner.address);
        }); 

        it('Should set the right transfer portal', async () => {
            await portal.connect(owner).setParameters(vault.address, JuiceToken.address, 100, 10);
            expect(await JuiceToken.transferPortal()).to.equal(portal.address);
        }); 

        it('Should assign the total supply of tokens to the owner', async () => {
            const ownerBalance = await JuiceToken.balanceOf(owner.address);
            expect(await JuiceToken.totalSupply()).to.equal(ownerBalance);
        });
    });

    describe('Transactions', () => {
        it('Should transfer tokens between accounts', async () => {

            await JuiceToken.transfer(addr1.address, 1000);

            const addr1Balance = await JuiceToken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(1000*0.989);

            const vaultBalance = await JuiceToken.balanceOf(vault.address)
            console.log("VAULT BALANCE="+vaultBalance)
        });

        it('Should fail if sender doesnt have enough tokens', async () => {
            const initialOwnerBalance = await JuiceToken.balanceOf(owner.address);
            await expect( JuiceToken.connect(addr1).transfer(owner.address, 1) )
                .to.be
                .revertedWith('ERC20: transfer amount exceeds balance');
            expect(await JuiceToken.balanceOf(owner.address))
                .to.equal(initialOwnerBalance)
        });

        it('Should update balance after transfers', async () => {
            const initialOwnerBalance = await JuiceToken.balanceOf(owner.address);

            await JuiceToken.transfer(addr1.address, 100);
            await JuiceToken.transfer(addr2.address, 50);

            const finalOwnerBalance = await JuiceToken.balanceOf(owner.address);
            expect(finalOwnerBalance).to.equal(initialOwnerBalance - 150);

            const addr1Balance = await JuiceToken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(99);

            const addr2Balance = await JuiceToken.balanceOf(addr2.address);
            expect(addr2Balance).to.equal(50);
        })
    })

    
    

  
});