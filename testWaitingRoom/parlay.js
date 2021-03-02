const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");


describe('Test Parlay Resolutions', () => {
    let  owner, addr1, addr2;
    beforeEach(async () => {
     
        tokenFactory = await ethers.getContractFactory('TestToken');
        token = await tokenFactory.deploy();
        sbFactory = await ethers.getContractFactory('TestParlay');
        sportsBook = await sbFactory.deploy(token.address, ["69","96"] ,["4","4"],[0,-100]);
        [owner, addr1, addr2, _] = await ethers.getSigners();
    });

    describe('Deployment', () => {
        it('Test', async () => {
            // token.connect(owner).mint(owner.address,100000000000000000000000);
            // token.connect(owner).mint(sportsBook.address,1000000000000000000000000000000000000000000000000000000);

        
        
            // await sportsBook.connect(owner).buildParlay("1323,3213","5,5",[95,-95])
        
        
            await sportsBook.connect(owner).resolveParlay('0x3139352c3335322c313832000000001230000000000000000000000000000000')
            // var ans = await sportsBook.ans()
            // console.log((parseInt(ans._hex,16)))

            // expect((parseInt(ans._hex,16))).to.equal(1);

        })

    });

 

});