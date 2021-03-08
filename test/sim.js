const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, BigNumber, constants } = require("ethers");
const { createWETH, createUniswap } = require("./helpers.js");

describe('Book Protocol Sim', () => {
    let owner, mesaj, aOne, aTwo, aThree, aFour, aFive;
    beforeEach(async () => {
        [owner, mesaj, aOne, aTwo, aThree, aFour, aFive] = await ethers.getSigners();
        weth = await createWETH();
        uniswap = await createUniswap(owner, weth);
        pair = uniswap.pairFor(await uniswap.factory.getPair(uniswap.wbtc.address, weth.address))
        DAI = await ethers.getContractFactory('Dai');
        wDAIContract = await ethers.getContractFactory('WDAI');
        BOOK = await ethers.getContractFactory('BookToken');
        TransferPortalFactory = await ethers.getContractFactory('TransferPortal');    
        BookLiqCalculatorFactory = await ethers.getContractFactory("LockedLiqCalculator");  
        SBGEContractFactory = await ethers.getContractFactory('SBGE'); 
        BookTreasuryFactory = await ethers.getContractFactory('BookTreasury');
        SportsBookFactory = await ethers.getContractFactory('TestSportsBook');
        BookVaultFactory = await ethers.getContractFactory('BookVault');
        BookSwapFactory = await ethers.getContractFactory('BookSwap');
        
        [owner, mesaj, lpMan, ethMan, aOne, aTwo, aThree, aFour, aFive, _] = await ethers.getSigners();

       
    });

    it('Uniswap should be initialized', async () => {
        expect(await uniswap.wbtc.address).to.not.equal(0x0);
        expect(await uniswap.factory.address).to.not.equal(0x0);
        expect(await uniswap.router.address).to.not.equal(0x0);
    }); 

    it('Sim', async () => {
        //Deploy
        const BOOKtoken = await BOOK.deploy("BOOK Token","BOOK", uniswap.dai.address, uniswap.factory.address);
        const BookVault = await BookVaultFactory.deploy(BOOKtoken.address);
        const portal = await TransferPortalFactory.deploy(BOOKtoken.address,uniswap.router.address);
        const DAItoken = await uniswap.dai;     
        const BookLiqCalculator = await BookLiqCalculatorFactory.deploy(BOOKtoken.address, uniswap.factory.address);
        await BOOKtoken.setTransferPortal(portal.address);
        const SportsBook = await SportsBookFactory.deploy(DAItoken.address); 
        const BookTreasury = await BookTreasuryFactory.deploy(BookVault.address, SportsBook.address, DAItoken.address, BOOKtoken.address, BookLiqCalculator.address, uniswap.factory.address, uniswap.router.address)
        const wDAI = await wDAIContract.deploy(BookVault.address, BOOKtoken.address, DAItoken.address, BookTreasury.address, uniswap.factory.address, "wDAI", "wDAI");
        const BookSwap = await BookSwapFactory.deploy(BOOKtoken.address,wDAI.address,uniswap.router.address)

        await BookTreasury.connect(owner).setWDAI(wDAI.address);
        await BOOKtoken.connect(owner).setWDAI(wDAI.address);
        await BOOKtoken.connect(owner).setBookVault(BookVault.address);
        // await SportsBook.connect(mesaj).setTreasury(BookTreasury.address);
        
        const sbge = await SBGEContractFactory.deploy(BOOKtoken.address, uniswap.router.address, wDAI.address, BookTreasury.address, weth.address);

        await wDAI.connect(owner).designateTreasury(sbge.address,true);
        //Promote owner and SBGE to Queastor of wDAI contract
        await wDAI.connect(owner).promoteQuaestor(sbge.address,true);
        await wDAI.connect(owner).promoteQuaestor(owner.address,true);
        await wDAI.connect(owner).setLiquidityCalculator(BookLiqCalculator.address);
        //Mint DAI to addresses to contribute to SBGE
        await DAItoken.connect(owner).mint(aTwo.address, utils.parseEther("30000"));
        await DAItoken.connect(owner).mint(aThree.address, utils.parseEther("20000000"));
        await DAItoken.connect(owner).mint(aFour.address, utils.parseEther("100000"));
        await DAItoken.connect(owner).mint(aFive.address, utils.parseEther("300000"));

        await weth.connect(mesaj).deposit({ value: utils.parseEther("50") });
        const WETHWBTC = uniswap.pairFor(await uniswap.factory.getPair(weth.address, uniswap.wbtc.address));
        await weth.connect(mesaj).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.router.connect(mesaj).swapExactTokensForTokens(15, 0, [weth.address, uniswap.wbtc.address], mesaj.address, 2e9);

        await weth.connect(lpMan).deposit({ value: utils.parseEther("50") });
        await weth.connect(lpMan).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.wbtc.connect(lpMan).approve(uniswap.router.address, constants.MaxUint256);
        await uniswap.router.connect(lpMan).swapExactTokensForTokens(15, 0, [weth.address, uniswap.wbtc.address], lpMan.address, 2e9);

        //LP man does LP man type things
        const wbtcBal = await uniswap.wbtc.balanceOf(lpMan.address)
        const wethBal = await weth.balanceOf(lpMan.address)
        await uniswap.router.connect(lpMan).addLiquidity(weth.address,uniswap.wbtc.address,wethBal,wbtcBal,0,0,lpMan.address,2e9)

        //Transfer Total BOOK Supply to SBGE
        await BOOKtoken.connect(owner).transfer(sbge.address, utils.parseEther("28000000"));

        await sbge.connect(owner).setupBOOKwdai();
        const BOOKwdai = uniswap.pairFor(await uniswap.factory.getPair(wDAI.address, BOOKtoken.address));

        await portal.connect(owner).allowPool(wDAI.address);
        await portal.connect(owner).setController(sbge.address, true);

        //activate SBGE
        await uniswap.wbtc.approve(sbge.address, constants.MaxUint256, { from: owner.address });
        await sbge.connect(owner).activate();
        
        //Approvals For Transfers
        await DAItoken.connect(owner).approve(BookSwap.address,constants.MaxUint256);
        await BOOKtoken.connect(owner).approve(BookSwap.address,constants.MaxUint256);
        await DAItoken.connect(aThree).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aThree).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aThree).approve(portal.address,constants.MaxUint256);
        await BOOKtoken.connect(aThree).approve(portal.address,constants.MaxUint256);
        await DAItoken.connect(aFour).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aFive).approve(sbge.address,constants.MaxUint256);
        await uniswap.wbtc.connect(mesaj).approve(sbge.address,constants.MaxUint256);
        await weth.connect(mesaj).approve(sbge.address,constants.MaxUint256);
        await BOOKwdai.connect(aThree).approve(BookVault.address,constants.MaxUint256);
        await BOOKwdai.connect(aFour).approve(BookVault.address,constants.MaxUint256);
        await BOOKwdai.connect(aFive).approve(BookVault.address,constants.MaxUint256);
        await BOOKwdai.connect(mesaj).approve(BookVault.address,constants.MaxUint256);
        await WETHWBTC.connect(lpMan).approve(sbge.address,constants.MaxUint256);
        await BOOKtoken.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await DAItoken.connect(aTwo).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await BOOKwdai.connect(aThree).approve(uniswap.router.address, constants.MaxUint256);

        //DAI Contribution Test
        await sbge.connect(aThree).contributeDAI(utils.parseEther("10000000"));
        await sbge.connect(aFour).contributeDAI(utils.parseEther("100000"));
        await sbge.connect(aFive).contributeDAI(utils.parseEther("300000"));

        expect(await sbge.daiContribution(aThree.address)).to.equal(utils.parseEther("10000000"));
        expect(await sbge.daiContribution(aFour.address)).to.equal(utils.parseEther("100000"));
        expect(await sbge.daiContribution(aFive.address)).to.equal(utils.parseEther("300000"));

        //ETH Contribution Test
        await ethMan.sendTransaction({ to: sbge.address, value: utils.parseEther("2") })
    
        //WETH Contribution Test
        await sbge.connect(mesaj).contributeToken(weth.address,utils.parseEther("2"));

        //LP Token Contribution Test
        await sbge.connect(lpMan).contributeToken(WETHWBTC.address,await WETHWBTC.balanceOf(lpMan.address));

        const sbgeDAIbalance = await DAItoken.balanceOf(sbge.address);
        console.log("SBGE Balance="+ utils.parseEther(''+sbgeDAIbalance))

       
        // wrap 30k DAI into wDAI
        await wDAI.connect(aTwo).deposit(utils.parseEther("30000"));

        //End SBGE
        await sbge.connect(owner).complete();

        //Init Book Transfer Portal
        await BOOKtoken.setTransferPortal(portal.address);
        await portal.connect(owner).setParameters(owner.address, BookVault.address, 100, 10);

        //Buy BOOK with wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        //aTwo sells BOOK for wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(await BOOKtoken.balanceOf(aTwo.address), 0, [BOOKtoken.address,wDAI.address], aTwo.address, 2e9);
        
        //Buy 10k wDAI worth of BOOK and then send it to aFive
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))

        //SBGE Contributors claim LP tokens and BOOK
        await sbge.connect(aThree).claim();
        await sbge.connect(aFour).claim();
        await sbge.connect(aFive).claim();
        await sbge.connect(mesaj).claim();

        //Create BOOK-wDAI pool to Vault
        await BookVault.connect(owner).addPool(10, BOOKwdai.address)
        expect(await BookVault.poolInfoCount()).to.equal(1);

        
        
        //Stake LP tokens to Vault
        const aThreeStakeAmt = await BOOKwdai.balanceOf(aThree.address);

        // console.log("removing liq")
        // expect(await uniswap.router.connect(aThree).removeLiquidity(BOOKtoken.address,wDAI.address,aThreeStakeAmt,0,0,aThree.address,2e9)).to.revert.with("UniswapV2: TRASNFER_FAILED")

        await BookVault.connect(aThree).deposit(0,aThreeStakeAmt)
        await BookVault.connect(aFour).deposit(0,await BOOKwdai.balanceOf(aFour.address))
        await BookVault.connect(aFive).deposit(0,await BOOKwdai.balanceOf(aFive.address))
        await BookVault.connect(mesaj).deposit(0,await BOOKwdai.balanceOf(mesaj.address))

        //Send accessible DAI liquidity to Treasury
        await wDAI.connect(owner).initializeTreasuryBalance(BookTreasury.address)
        const final = await DAItoken.balanceOf(BookTreasury.address)
        console.log("Final Treasury DAI Token Balance="+(final/10e17))

        //Buy BOOK from LP with wDAI and transfer it
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, BOOKtoken.address], aTwo.address, 2e9);
        await BOOKtoken.connect(aTwo).transfer(aFive.address, await BOOKtoken.balanceOf(aTwo.address))


        //Test Book Swap
        await portal.connect(owner).noTaxation(BookSwap.address,true)
        await DAItoken.connect(owner).mint(owner.address, utils.parseEther("10000000"))
        await BookSwap.connect(owner).buyBookwithDAI(utils.parseEther("10000"))
        await BookSwap.connect(owner).sellBookforDAI(utils.parseEther("10000"))

        
        console.log("aThree Pending Reward=" + await BookVault.pendingReward(0,aThree.address))
  

        // aThree Withdraws from Vault - Should receive Book Token Reward
        const pre = await BOOKtoken.balanceOf(aThree.address);
        // console.log("pre="+pre)
        await BookVault.connect(aThree).withdraw(0,aThreeStakeAmt); //should receive some BOOK reward when they withdraw
        const post = await BOOKtoken.balanceOf(aThree.address);
        // console.log("post="+post)
        expect(post).to.not.equal(pre);

        // await BookTreasury.connect(owner).getMinRequiredVotes();
   
        // await BookTreasury.connect(owner).numberGoUp(treasuryDAI)

        await wDAI.connect(aThree).deposit(utils.parseEther("50000"));



        const BOOKbalance = await BOOKtoken.balanceOf(BOOKwdai.address)
        // console.log("book="+BOOKbalance)

        const WDAIbalance = await wDAI.balanceOf(BOOKwdai.address)
        // console.log("wdai="+WDAIbalance)

        // console.log(WDAIbalance/BOOKbalance)

        // const wDAIamt = Number(1000000000000000000000/BOOKbalance*WDAIbalance)
        // const BOOKamt = Number(1000000000000000000000)

        // console.log(wDAIamt)
        // console.log(BOOKamt)

        //Check SafeAddLiquidity Function in Transfer Portal
        const check1 = await BOOKwdai.balanceOf(aThree.address)
        // console.log(parseInt(check1._hex))
        await portal.connect(aThree).safeAddLiquidity(wDAI.address, 1000, (1000*WDAIbalance/BOOKbalance).toFixed(0),0,0,aThree.address,2e9)
        const check2 = await BOOKwdai.balanceOf(aThree.address)
        // console.log(parseInt(check2._hex))
        expect(check1).to.not.equal(check2);
        // console.log("Final Treasury DAI Token Balance="+final2/10e18)
    }); 

  
});