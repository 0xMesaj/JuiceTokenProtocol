const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, BigNumber, constants } = require("ethers");
const { createWETH, createUniswap } = require("./helpers.js");
// const WBTC = artifacts.require('WBTC');


describe('Book Protocol Sim', () => {
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
        SportsBookFactory = await ethers.getContractFactory('SportsBook');
        BookVaultFactory = await ethers.getContractFactory('BookVault');
        
        [owner, mesaj, lpMan, aOne, aTwo, aThree, aFour, aFive, _] = await ethers.getSigners();

       
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
        const SportsBook = await SportsBookFactory.deploy(); 
        const BookTreasury = await BookTreasuryFactory.deploy(SportsBook.address,DAItoken.address,BOOKtoken.address, BookLiqCalculator.address, uniswap.factory.address, uniswap.router.address)
        const wDAI = await wDAIContract.deploy(DAItoken.address, BookTreasury.address, "wDAI", "wDAI");
        await BookTreasury.connect(owner).setWDAI(wDAI.address);
        // await SportsBook.connect(mesaj).setTreasury(BookTreasury.address);
        
        const sbge = await SBGEContractFactory.deploy(BOOKtoken.address, uniswap.router.address, wDAI.address, BookTreasury.address, weth.address);

        await wDAI.connect(owner).designateTreasury(sbge.address,true);
        //Promote owner and SBGE to Queastor of wDAI contract
        await wDAI.connect(owner).promoteQuaestor(sbge.address,true);
        await wDAI.connect(owner).promoteQuaestor(owner.address,true);
        await wDAI.connect(owner).setLiquidityCalculator(BookLiqCalculator.address);
        //Mint DAI to addresses to contribute to SBGE
        await DAItoken.connect(owner).mint(aTwo.address, 30000);
        await DAItoken.connect(owner).mint(aThree.address, 10000000);
        await DAItoken.connect(owner).mint(aFour.address, 100000);
        await DAItoken.connect(owner).mint(aFive.address, 300000);

        await weth.connect(mesaj).deposit({ value: utils.parseEther("50") });
        const WETHWBTC = uniswap.pairFor(await uniswap.factory.getPair(weth.address, uniswap.wbtc.address));
        await weth.connect(mesaj).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.router.connect(mesaj).swapExactTokensForTokens(15, 0, [weth.address, uniswap.wbtc.address], mesaj.address, 2e9);

        await weth.connect(lpMan).deposit({ value: utils.parseEther("50") });
        await weth.connect(lpMan).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.wbtc.connect(lpMan).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.router.connect(lpMan).swapExactTokensForTokens(15, 0, [weth.address, uniswap.wbtc.address], lpMan.address, 2e9);

        // console.log("BEFORE lpMan LP TOKEN BALANCE : "+await WETHWBTC.balanceOf(lpMan.address))
        // console.log("BEFORE lpMan WBTC BALANCE : "+await uniswap.wbtc.balanceOf(lpMan.address))
        const wbtcBal = await uniswap.wbtc.balanceOf(lpMan.address)
        const wethBal = await weth.balanceOf(lpMan.address)
        await uniswap.router.connect(lpMan).addLiquidity(weth.address,uniswap.wbtc.address,wethBal,wbtcBal,0,0,lpMan.address,2e9)
        // console.log("AFTER lpMan LP TOKEN BALANCE : "+await WETHWBTC.balanceOf(lpMan.address))
        // console.log("AFTER lpMan WBTC BALANCE : "+await uniswap.wbtc.balanceOf(lpMan.address))
        
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
        await WETHWBTC.connect(lpMan).approve(sbge.address,constants.MaxUint256);
        
        await sbge.connect(aThree).contributeDAI(10000000);
        await sbge.connect(aFour).contributeDAI(100000);
        await sbge.connect(aFive).contributeDAI(300000);

        /* ~Test Contributing Token othan than DAI or UNI/Sushi LP Token~ */
        // console.log("SBGE DAI BALANCE PRE WBTC SALE : "+await DAItoken.balanceOf(sbge.address))
        // console.log("MESAJ wbtc BALANCE: "+await uniswap.wbtc.balanceOf(mesaj.address))
        await sbge.connect(mesaj).contributeToken(weth.address,5);
        // console.log("SBGE DAI BALANCE POST WBTC SALE: "+await DAItoken.balanceOf(sbge.address))
        //console.log("MESAJ SBGE CONTRIBUTION POST WBTC SALE: "+ await sbge.connect(mesaj).daiContribution(mesaj.address))

        console.log("lpMan SBGE CONTRIBUTION PRE: "+ await sbge.connect(lpMan).daiContribution(lpMan.address))
        await sbge.connect(lpMan).contributeToken(WETHWBTC.address,await WETHWBTC.balanceOf(lpMan.address));
        console.log("lpMan SBGE CONTRIBUTION POST: "+ await sbge.connect(lpMan).daiContribution(lpMan.address))

        expect(await sbge.daiContribution(aThree.address)).to.equal(10000000);
        expect(await sbge.daiContribution(aFour.address)).to.equal(100000);
        expect(await sbge.daiContribution(aFive.address)).to.equal(300000);

        const sbgeDAIbalance = await DAItoken.balanceOf(sbge.address);
        console.log("SBGE Balance="+sbgeDAIbalance)

        //aTwo wraps 30k DAI into 30k wDAI and buys BOOK from LP
        await DAItoken.connect(aTwo).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aTwo).deposit(30000);
        await wDAI.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await BOOKtoken.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        
        // await TransferPortal.connect(owner).allowPool(wDAI.address);
    
        // expect(await wDAI.balanceOf(aTwo.address)).to.equal(10000);

        //End SBGE
        await sbge.connect(owner).complete();

        await BOOKtoken.setTransferPortal(portal.address);
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

        await BookTreasury.connect(owner).sendToken(DAItoken.address, SportsBook.address,await DAItoken.balanceOf(BookTreasury.address))

        console.log("Final SportsBook DAI Balance="+await DAItoken.balanceOf(SportsBook.address))
        console.log("Final Book Vault BOOK Token Balance="+await BOOKtoken.balanceOf(BookVault.address))

        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(10000, 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))

        // console.log("aThree Pending Reward=" + await BookVault.pendingReward(0,aThree.address))

        // await BookVault.updatePool(0);

        //aThree Withdraws from Vault - Should receive Book Token Reward
        const pre = await BOOKtoken.balanceOf(aThree.address);
        await BookVault.connect(aThree).withdraw(0,aThreeStakeAmt); //should receive some BOOK reward when they withdraw
        const post = await BOOKtoken.balanceOf(aThree.address);
        expect(post > pre);

        //Place a Bet
        await SportsBook.connect(mesaj).bet('0x0efcbf1a844424573dd8de90cc11d9ff','15793','5',100,3);
        // await SportsBook.connect(mesaj).betParlay('0x0efcbf1a844424573dd8de90cc11d9ff',123,[123456789,987654321,123456789,123456789,987654321,123456789,123456789],[4444456789,987654321,123456789,123456789,987654321,123456789,123456789],
        // [333456789,987654321,123456789,123456789,987654321,123456789,123456789])
    }); 

  
});