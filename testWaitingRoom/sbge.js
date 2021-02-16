const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, BigNumber, constants } = require("ethers");
const { createWETH, createUniswap } = require("../test/helpers.js");
// const WBTC = artifacts.require('WBTC');


describe('SBGE Sim', () => {
    let BOOK, bookLiquidityFactory, weth, wDAIContract, DAI, TransferPortal, owner, mesaj, aOne, aTwo, aThree, aFour, aFive;
    beforeEach(async () => {
        [owner, mesaj, aOne, aTwo, aThree, aFour, aFive] = await ethers.getSigners();
        weth = await createWETH();
        uniswap = await createUniswap(owner, weth);
        pair = uniswap.pairFor(await uniswap.factory.getPair(uniswap.wbtc.address, weth.address))
        DAI = await ethers.getContractFactory('Dai');
        wDAIContract = await ethers.getContractFactory('WDAI');
        BOOK = await ethers.getContractFactory('BookToken');
        TransferPortalFactory = await ethers.getContractFactory('TransferPortal');   
        bookLiquidityFactory = await ethers.getContractFactory("BookLiquidity");   
        BookLiqCalculatorFactory = await ethers.getContractFactory("LockedLiqCalculator");  
        SBGEContractFactory = await ethers.getContractFactory('SBGE'); 
        BookTreasuryFactory = await ethers.getContractFactory('BookTreasury');
        
        [owner, mesaj, aOne, aTwo, aThree, aFour, aFive, _] = await ethers.getSigners();

       
    });

    it('Uniswap should be initialized', async () => {
        // console.log("Router Address = "+uniswap.router.address)
        // console.log("Factory Address = "+uniswap.factory.address)
        // console.log("WBTC Address = "+uniswap.wbtc.address)
        expect(await uniswap.wbtc.address).to.not.equal(0x0);
        expect(await uniswap.factory.address).to.not.equal(0x0);
        expect(await uniswap.router.address).to.not.equal(0x0);
    }); 

    it('Sim', async () => {
        //Deploy Contracts
        const BookTreasury = await BookTreasuryFactory.deploy()
        const BOOKtoken = await BOOK.deploy("BOOK Token","BOOK");
        const portal = await TransferPortalFactory.deploy(BOOKtoken.address);
        // const DAItoken = await DAI.deploy();
        const DAItoken = await uniswap.dai;
        const wDAI = await wDAIContract.deploy(DAItoken.address, "wDAI", "wDAI");
        const sbge = await SBGEContractFactory.deploy(BOOKtoken.address, uniswap.router.address, wDAI.address, BookTreasury.address, weth.address);
        const BookLiqCalculator = await BookLiqCalculatorFactory.deploy(BOOKtoken.address, uniswap.factory.address);
       
        //Mint DAI to addresses to contribute to SBGE
        await DAItoken.connect(owner).mint(aTwo.address, 20000);
        await DAItoken.connect(owner).mint(aThree.address, 10000000);
        await DAItoken.connect(owner).mint(aFour.address, 100000);
        await DAItoken.connect(owner).mint(aFive.address, 300000);

        await weth.connect(mesaj).deposit({ value: utils.parseEther("50") });
        const WETHWBTC = uniswap.pairFor(await uniswap.factory.getPair(weth.address, uniswap.wbtc.address));
        await weth.connect(mesaj).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.router.connect(mesaj).swapExactTokensForTokens(15, 0, [weth.address, uniswap.wbtc.address], mesaj.address, 2e9);

        // const ownerDAIbalance = await DAItoken.balanceOf(owner.address);
        
        //Transfer Total BOOK Supply to SBGE
        await BOOKtoken.connect(owner).transfer(sbge.address, 28000000);

        await sbge.connect(owner).setupBOOKwdai();
        const BOOKwdai = uniswap.pairFor(await uniswap.factory.getPair(wDAI.address, BOOKtoken.address));
        const wrappedBOOKwdai = await bookLiquidityFactory.connect(owner).deploy(BOOKwdai.address, "wrappedBOOKwdai", "WDAIBOOK");
        await sbge.connect(owner).completeSetup(wrappedBOOKwdai.address);

        await portal.connect(owner).setUnrestrictedController(sbge.address, true);

        const sbgeBalance = await BOOKtoken.balanceOf(sbge.address);

        expect(await BOOKtoken.totalSupply()).to.equal(sbgeBalance);

        //activate SBGE
        await uniswap.wbtc.approve(sbge.address, constants.MaxUint256, { from: owner.address });
        await sbge.connect(owner).activate();
        

        await DAItoken.connect(aThree).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aFour).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aFive).approve(sbge.address,constants.MaxUint256);
        await uniswap.wbtc.connect(mesaj).approve(sbge.address,constants.MaxUint256);
        await weth.connect(mesaj).approve(sbge.address,constants.MaxUint256);

        await wDAI.connect(owner).setLiquidityCalculator(BookLiqCalculator.address);
        await sbge.connect(aThree).contributeDAI(10000000);
        await sbge.connect(aFour).contributeDAI(100000);
        await sbge.connect(aFive).contributeDAI(300000);
        // console.log("SBGE DAI BALANCE PRE WBTC SALE : "+await DAItoken.balanceOf(sbge.address))
        // console.log("MESAJ wbtc BALANCE: "+await uniswap.wbtc.balanceOf(mesaj.address))
        await sbge.connect(mesaj).contributeToken(weth.address,5);
        // console.log("SBGE DAI BALANCE POST WBTC SALE: "+await DAItoken.balanceOf(sbge.address))
        //console.log("MESAJ SBGE CONTRIBUTION POST WBTC SALE: "+ await sbge.connect(mesaj).daiContribution(mesaj.address))

        expect(await sbge.daiContribution(aThree.address)).to.equal(10000000);
        expect(await sbge.daiContribution(aFour.address)).to.equal(100000);
        expect(await sbge.daiContribution(aFive.address)).to.equal(300000);

        const sbgeDAIbalance = await DAItoken.balanceOf(sbge.address);
        console.log("SBGE Balance="+sbgeDAIbalance)

        //aTwo wraps 10k DAI into 10k wDAI and buys BOOK from LP
        await DAItoken.connect(aTwo).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aTwo).deposit(20000);
        await wDAI.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await BOOKtoken.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        
        // await TransferPortal.connect(owner).allowPool(wDAI.address);
        

        // expect(await wDAI.balanceOf(aTwo.address)).to.equal(10000);

        //complete SBGE
        await sbge.connect(owner).complete();

        await BOOKtoken.setTransferPortal(portal.address);
        await portal.connect(owner).setParameters(owner.address, BookTreasury.address, 100, 10);

        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        // console.log("aTwo BOOK Balance="+await BOOKtoken.balanceOf(aTwo.address))
       
        // Sweep Floor To Vault
        // await wDAI.connect(owner).sweepFloor(vault.address)

        // const BOOKBal = await BOOKtoken.balanceOf(aTwo.address)
        // console.log("BOOKBal After 20k wDAI Purchase="+BOOKBal);

        //aTwo sells BOOK for wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(await BOOKtoken.balanceOf(aTwo.address), 0, [BOOKtoken.address,wDAI.address], aTwo.address, 2e9);

        //Buy 10k wDAI worth of BOOK and then send it to aFive
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        // console.log("Before:"+await BOOKtoken.balanceOf(aTwo.address))
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))
        // console.log("After:"+await BOOKtoken.balanceOf(aFive.address))

        await sbge.connect(aThree).claim();
        await sbge.connect(aFour).claim();
        await sbge.connect(aFive).claim();
        await sbge.connect(mesaj).claim();
        // console.log("aThree LP Token Balance="+await wrappedBOOKwdai.balanceOf(aThree.address));
        // console.log("aFour LP Token Balance="+await wrappedBOOKwdai.balanceOf(aFour.address))
        // console.log("aFive LP Token Balance="+await wrappedBOOKwdai.balanceOf(aFive.address))
        // console.log("Mesaj LP Token Balance="+await wrappedBOOKwdai.balanceOf(mesaj.address))
        // console.log("Mesaj BOOK Balance="+await BOOKtoken.balanceOf(mesaj.address));
        // console.log("aThree BOOK Balance="+await BOOKtoken.balanceOf(aThree.address));
        // console.log("aFour BOOK Balance="+await BOOKtoken.balanceOf(aFour.address))
        // console.log("aFive BOOK Balance="+await BOOKtoken.balanceOf(aFive.address))

        
        console.log("Final Vault DAI Balance="+await DAItoken.balanceOf(BookTreasury.address))
        console.log("Final Owner DAI Balance="+await DAItoken.balanceOf(owner.address))
        console.log("Final wDAI Contract DAI Balance="+await DAItoken.balanceOf(wDAI.address))

    }); 





    // describe('Deployment', () => {
    //     it('Should set the right owner', async () => {
    //         expect(await BOOKtoken.owner()).to.equal(owner.address);
    //     }); 

    //     it('Should set the right transfer portal', async () => {
    //         await portal.connect(owner).setParameters(vault.address, BOOKtoken.address, 100, 10);
    //         expect(await BOOKtoken.transferPortal()).to.equal(portal.address);
    //     }); 

    //     it('Should assign the total supply of tokens to the owner', async () => {
    //         const ownerBalance = await BOOKtoken.balanceOf(owner.address);
    //         expect(await BOOKtoken.totalSupply()).to.equal(ownerBalance);
    //     });
    // });

   
    
    

  
});