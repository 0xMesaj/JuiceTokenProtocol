const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, BigNumber, constants } = require("ethers");
const { createWETH, createUniswap } = require("../test/helpers.js");
// const WBTC = artifacts.require('WBTC');


describe('Test Sports Book Betting Sim', () => {
    let BOOK, bookLiquidityFactory, weth, wDAIContract, owner, mesaj, aOne, aTwo, aThree, aFour, aFive;
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
        SportsBookFactory = await ethers.getContractFactory('TestSportsBook');
        BookVaultFactory = await ethers.getContractFactory('BookVault');
        
        [owner, mesaj, aOne, aTwo, aThree, aFour, aFive,gambling_addict, _] = await ethers.getSigners();

       
    });

    it('Uniswap should be initialized', async () => {
        expect(await uniswap.wbtc.address).to.not.equal(0x0);
        expect(await uniswap.factory.address).to.not.equal(0x0);
        expect(await uniswap.router.address).to.not.equal(0x0);
    }); 

    it('Sim', async () => {
        
        // console.log("Router Address = "+uniswap.router.address)
        // console.log("Factory Address = "+uniswap.factory.address)
        // console.log("WBTC Address = "+uniswap.wbtc.address)

        //Deploy
        const BOOKtoken = await BOOK.deploy("BOOK Token","BOOK");
        const BookVault = await BookVaultFactory.deploy(BOOKtoken.address);
        const portal = await TransferPortalFactory.deploy(BOOKtoken.address,uniswap.router.address);
        const DAItoken = await uniswap.dai;     
        const BookLiqCalculator = await BookLiqCalculatorFactory.deploy(BOOKtoken.address, uniswap.factory.address);
        await BOOKtoken.setTransferPortal(portal.address);
        const SportsBook = await SportsBookFactory.deploy(DAItoken.address); 
        const BookTreasury = await BookTreasuryFactory.deploy(SportsBook.address,DAItoken.address,BOOKtoken.address, BookLiqCalculator.address, uniswap.factory.address, uniswap.router.address)
        const wDAI = await wDAIContract.deploy(DAItoken.address, BookTreasury.address, "wDAI", "wDAI");
        await BookTreasury.connect(owner).setWDAI(wDAI.address);
        await SportsBook.connect(mesaj).setTreasury(BookTreasury.address);
        
        const sbge = await SBGEContractFactory.deploy(BOOKtoken.address, uniswap.router.address, wDAI.address, BookTreasury.address, weth.address);

        //Send 10 Eth to Sports Book
        await owner.sendTransaction({ to: SportsBook.address, value: utils.parseEther("10") });

        await BOOKtoken.setTransferPortal(portal.address);
        await wDAI.connect(owner).designateTreasury(sbge.address,true);

        //Promote SBGE to Queastor of wDAI contract so it can call fund()
        await wDAI.connect(owner).promoteQuaestor(sbge.address,true);

        await wDAI.connect(owner).setLiquidityCalculator(BookLiqCalculator.address);
        //Mint DAI to addresses to contribute to SBGE
        await DAItoken.connect(owner).mint(aTwo.address, 30000);
        await DAItoken.connect(owner).mint(aThree.address, 10000000);
        await DAItoken.connect(owner).mint(aFour.address, 100000);
        await DAItoken.connect(owner).mint(aFive.address, 300000);
        await DAItoken.connect(owner).mint(gambling_addict.address, 10000000000);    //Give gambling_addict a bunch of Dai to bet with

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

        await portal.connect(owner).allowPool(wDAI.address);
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
        await wrappedBOOKwdai.connect(aThree).approve(BookVault.address,constants.MaxUint256);  //for staking to vault
        await wrappedBOOKwdai.connect(aFour).approve(BookVault.address,constants.MaxUint256);
        await wrappedBOOKwdai.connect(aFive).approve(BookVault.address,constants.MaxUint256);
        await wrappedBOOKwdai.connect(mesaj).approve(BookVault.address,constants.MaxUint256);
        
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

        //aTwo wraps 30k DAI into 30k wDAI and buys BOOK from LP
        await DAItoken.connect(aTwo).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aTwo).deposit(30000);
        await wDAI.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await BOOKtoken.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        
        // await TransferPortal.connect(owner).allowPool(wDAI.address);
    
        // expect(await wDAI.balanceOf(aTwo.address)).to.equal(10000);

        //End SBGE
        await sbge.connect(owner).complete();

        
        await portal.connect(owner).setParameters(owner.address, BookVault.address, 100, 10);
        
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
       
        //aTwo sells BOOK for wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(await BOOKtoken.balanceOf(aTwo.address), 0, [BOOKtoken.address,wDAI.address], aTwo.address, 2e9);
        
        //Buy 10k wDAI worth of BOOK and then send it to aFive
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))

        //SBGE Contributors claim LP tokens and BOOK
        await sbge.connect(aThree).claim();
        await sbge.connect(aFour).claim();
        await sbge.connect(aFive).claim();
        await sbge.connect(mesaj).claim();

        
        await BookVault.connect(owner).addPool(10, wrappedBOOKwdai.address)
        // console.log("Pool Info Token="+(await BookVault.poolInfo(0)))
        expect(await BookVault.poolInfoCount()).to.equal(1);

        const aThreeStakeAmt = await wrappedBOOKwdai.balanceOf(aThree.address);
        await BookVault.connect(aThree).deposit(0,aThreeStakeAmt)
        await BookVault.connect(aFour).deposit(0,await wrappedBOOKwdai.balanceOf(aFour.address))
        await BookVault.connect(aFive).deposit(0,await wrappedBOOKwdai.balanceOf(aFive.address))
        await BookVault.connect(mesaj).deposit(0,await wrappedBOOKwdai.balanceOf(mesaj.address))

        // console.log("Final Owner DAI Balance="+await DAItoken.balanceOf(owner.address))
        // console.log("Final wDAI Contract DAI Balance="+await DAItoken.balanceOf(wDAI.address))


        // await BookTreasury.connect(owner).sendToken(DAItoken.address, SportsBook.address,await DAItoken.balanceOf(BookTreasury.address))
        
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))

        // console.log("aThree Pending Reward=" + await BookVault.pendingReward(0,aThree.address))

        // await BookVault.updatePool(0);

        //aThree Withdraws from Vault - Should receive Book Token Reward
        const pre = await BOOKtoken.balanceOf(aThree.address);
        await BookVault.connect(aThree).withdraw(0,aThreeStakeAmt); //should receive some BOOK reward when they withdraw
        const post = await BOOKtoken.balanceOf(aThree.address);
        expect(post > pre);

        // Place a Bet
        // console.log("Treasury dai Balance="+ await DAItoken.balanceOf(BookTreasury.address))

        await DAItoken.connect(gambling_addict).approve(SportsBook.address,constants.MaxUint256);
        await SportsBook.connect(gambling_addict).bet(100000,false);
        await SportsBook.connect(gambling_addict).bet(100000,false);
        await SportsBook.connect(gambling_addict).bet(10000,true);
        await SportsBook.connect(gambling_addict).bet(100000,false);

        //DAI from wDAI contract to Treasury
        await wDAI.connect(owner).fund(BookTreasury.address)

        console.log("Vault BOOK Balance="+ await BOOKtoken.balanceOf(BookVault.address))

        //Use DAI from Treasury to buy book token
        await BookTreasury.connect(owner).numberGoUp(100000);
        console.log("After buy Vault BOOK Balance="+ await BOOKtoken.balanceOf(BookVault.address))

        // console.log("12: Treasury DAI balance="+ await DAItoken.balanceOf(BookTreasury.address))
        await wDAI.connect(owner).fund(BookTreasury.address)
        // console.log("34: Treasury DAI balance="+ await DAItoken.balanceOf(BookTreasury.address))

    }); 
});