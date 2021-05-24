const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, constants } = require("ethers");


describe('Test Parlay Resolutions', () => {
    let  owner, addr1, addr2;
    beforeEach(async () => {
     
        tokenFactory = await ethers.getContractFactory('TestToken');
        token = await tokenFactory.deploy();
        sbFactory = await ethers.getContractFactory('TestParlay');
        sportsBook = await sbFactory.deploy(token.address);
        [owner, addr1, addr2, _] = await ethers.getSigners();
    });

    describe('Deployment', () => {
        it('Test', async () => {
            // token.connect(owner).mint(owner.address,100000000000000000000000);
            // token.connect(owner).mint(sportsBook.address,1000000000000000000000000000000000000000000000000000000);

        
        
            // await sportsBook.connect(owner).buildParlay("1323,3213","5,5",[95,-95])
        
            await sportsBook.connect(owner).betParlay('0x70a6a75c0d33c2a7597ba2d25252ce5a',10000,"16588,16589,16588,16589","0,4,0,4",[10,0,10,0])
            // await sportsBook.connect(owner).testLook('0x70a6a75c0d33c2a7597ba2d25252ce5a',1)
            // await sportsBook.connect(owner).testValue()
            // .then( (res) => console.log(parseInt(res._hex)))

            await sportsBook.connect(owner).refundParlay('0x70a6a75c0d33c2a7597ba2d25252ce5a')

        })

    });

 

});