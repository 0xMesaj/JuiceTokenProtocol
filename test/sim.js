const { expect } = require('chai');
const { ethers } = require('hardhat');
const { utils, BigNumber, constants } = require("ethers");
const { createWETH, createUniswap } = require("./helpers.js");

describe('Juice Protocol Sim', () => {
    let owner, mesaj, aOne, aTwo, aThree, aFour, aFive;
    beforeEach(async () => {
        [owner, mesaj, aOne, aTwo, aThree, aFour, aFive] = await ethers.getSigners();
        weth = await createWETH();
        uniswap = await createUniswap(owner, weth);
        pair = uniswap.pairFor(await uniswap.factory.getPair(uniswap.wbtc.address, weth.address))
        DAI = await ethers.getContractFactory('Dai');
        wDAIContract = await ethers.getContractFactory('WDAI');
        JUICE = await ethers.getContractFactory('JuiceToken');
        TransferPortalFactory = await ethers.getContractFactory('TransferPortal');    
        LiqCalculatorFactory = await ethers.getContractFactory("LockedLiqCalculator");  
        SBGEContractFactory = await ethers.getContractFactory('SBGE'); 
        JuiceTreasuryFactory = await ethers.getContractFactory('JuiceTreasury');
        SportsBookFactory = await ethers.getContractFactory('TestSportsBook');
        JuiceVaultFactory = await ethers.getContractFactory('JuiceVault');
        JuiceBookSwapFactory = await ethers.getContractFactory('JuiceBookSwap');
        BridgeToXDAIFactory = await ethers.getContractFactory('BridgeToXDAI');
    
        [owner, mesaj, lpMan, ethMan, aOne, aTwo, aThree, aFour, aFive, _] = await ethers.getSigners();
    });

    it('Uniswap should be initialized', async () => {
        expect(await uniswap.wbtc.address).to.not.equal(0x0);
        expect(await uniswap.factory.address).to.not.equal(0x0);
        expect(await uniswap.router.address).to.not.equal(0x0);
    }); 

    it('Sim', async () => {
        //Deploy
        const DAItoken = await uniswap.dai;
        const xDAISportsBook = await SportsBookFactory.deploy(DAItoken.address); 
        const xDaiBridge = await BridgeToXDAIFactory.deploy(xDAISportsBook.address,DAItoken.address)
        const JUICEtoken = await JUICE.deploy("JuiceToken","JCE");
        const JuiceVault = await JuiceVaultFactory.deploy(JUICEtoken.address);
        const portal = await TransferPortalFactory.deploy(JUICEtoken.address,uniswap.router.address);
        const LiqCalculator = await LiqCalculatorFactory.deploy(JUICEtoken.address, uniswap.factory.address);
        await JUICEtoken.setTransferPortal(portal.address);
        const SportsBook = await SportsBookFactory.deploy(DAItoken.address); 
        const JuiceTreasury = await JuiceTreasuryFactory.deploy(JuiceVault.address, SportsBook.address, xDaiBridge.address, DAItoken.address, JUICEtoken.address, LiqCalculator.address);
        await xDaiBridge.connect(owner).setTreasury(JuiceTreasury.address);
        const wDAI = await wDAIContract.deploy(JuiceVault.address, JUICEtoken.address, DAItoken.address, JuiceTreasury.address, "wDAI", "wDAI");
        const JuiceBookSwap = await JuiceBookSwapFactory.deploy(JUICEtoken.address,wDAI.address,uniswap.router.address);

        await JuiceTreasury.connect(owner).setWDAI(wDAI.address);
        
        await JUICEtoken.connect(owner).setJCEVault(JuiceVault.address);
        
        const sbge = await SBGEContractFactory.deploy(JUICEtoken.address, wDAI.address, JuiceTreasury.address, weth.address,uniswap.router.address);

        await wDAI.connect(owner).designateTreasury(sbge.address,true);
        //Promote owner and SBGE to Quaestor of wDAI contract
        await wDAI.connect(owner).promoteQuaestor(sbge.address,true);
        await wDAI.connect(owner).promoteQuaestor(owner.address,true);
        await wDAI.connect(owner).setLiquidityCalculator(LiqCalculator.address);
        //END Set up


        //Mint DAI to addresses to contribute to SBGE
        await DAItoken.connect(owner).mint(aTwo.address, utils.parseEther("30000"));
        await DAItoken.connect(owner).mint(aThree.address, utils.parseEther("20000000"));
        await DAItoken.connect(owner).mint(aFour.address, utils.parseEther("100000000"));
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

        //Transfer Total JCE Supply to SBGE
        await JUICEtoken.connect(owner).transfer(sbge.address, utils.parseEther("28000000"));

        await sbge.connect(owner).setupJCEwdai();
        const JCEwdai = uniswap.pairFor(await uniswap.factory.getPair(wDAI.address, JUICEtoken.address));

        await portal.connect(owner).allowPool(wDAI.address);
        await portal.connect(owner).setWard(sbge.address);

        // Activate SBGE
        await uniswap.wbtc.approve(sbge.address, constants.MaxUint256, { from: owner.address });
        await sbge.connect(owner).activate();
        
        // Approvals
        await DAItoken.connect(owner).approve(JuiceBookSwap.address,constants.MaxUint256);
        await JUICEtoken.connect(owner).approve(JuiceBookSwap.address,constants.MaxUint256);
        await DAItoken.connect(aThree).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aThree).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aThree).approve(portal.address,constants.MaxUint256);
        await JUICEtoken.connect(aThree).approve(portal.address,constants.MaxUint256);
        await DAItoken.connect(aFour).approve(sbge.address,constants.MaxUint256);
        await DAItoken.connect(aFive).approve(sbge.address,constants.MaxUint256);
        await uniswap.wbtc.connect(mesaj).approve(sbge.address,constants.MaxUint256);
        await weth.connect(mesaj).approve(sbge.address,constants.MaxUint256);
        await JCEwdai.connect(aThree).approve(JuiceVault.address,constants.MaxUint256);
        await JCEwdai.connect(aFour).approve(JuiceVault.address,constants.MaxUint256);
        await JCEwdai.connect(aFive).approve(JuiceVault.address,constants.MaxUint256);
        await JCEwdai.connect(mesaj).approve(JuiceVault.address,constants.MaxUint256);
        await WETHWBTC.connect(lpMan).approve(sbge.address,constants.MaxUint256);
        await JUICEtoken.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await DAItoken.connect(aTwo).approve(wDAI.address,constants.MaxUint256);
        await wDAI.connect(aTwo).approve(uniswap.router.address, constants.MaxUint256);
        await JCEwdai.connect(aThree).approve(uniswap.router.address, constants.MaxUint256);

        //DAI Contribution Test
        console.log("aThree Contributing 1,000,00 DAI to SBGE...")
        var preDAI = await sbge.daiContribution(aThree.address)
        await sbge.connect(aThree).contributeDAI(utils.parseEther("1000000"));
        var postDAI = await sbge.daiContribution(aThree.address)
        console.log("Contribution Successful... New Contribution: " + (postDAI/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preDAI/10 ** 18).toFixed(2))
        console.log("---------------------------")
        expect(await sbge.daiContribution(aThree.address)).to.equal(utils.parseEther("1000000"));

        console.log("aFour Contributing 100,000 DAI to SBGE...")
        preDAI = await sbge.daiContribution(aFour.address)
        await sbge.connect(aFour).contributeDAI(utils.parseEther("100000"));
        postDAI = await sbge.daiContribution(aFour.address)
        console.log("Contribution Successful... New Contribution: " + (postDAI/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preDAI/10 ** 18).toFixed(2))
        console.log("---------------------------")

        console.log("aFour Contributing 100,000 DAI to SBGE...")
        preDAI = await sbge.daiContribution(aFour.address)
        await sbge.connect(aFour).contributeDAI(utils.parseEther("100000"));
        postDAI = await sbge.daiContribution(aFour.address)
        console.log("Contribution Successful... New Contribution: " + (postDAI/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preDAI/10 ** 18).toFixed(2))
        console.log("---------------------------")
        expect(await sbge.daiContribution(aFour.address)).to.equal(utils.parseEther("200000"));

        console.log("aFive Contributing 300,000 DAI to SBGE...")
        preDAI = await sbge.daiContribution(aFive.address)
        await sbge.connect(aFive).contributeDAI(utils.parseEther("300000"));
        postDAI = await sbge.daiContribution(aFive.address)
        console.log("Contribution Successful... New Contribution: " + (postDAI/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preDAI/10 ** 18).toFixed(2))
        console.log("---------------------------")
        expect(await sbge.daiContribution(aFive.address)).to.equal(utils.parseEther("300000"));

        //ETH Contribution Test
        console.log("Eth Man Contributing 2 ETH to SBGE...")
        var preETH = await sbge.daiContribution(ethMan.address)
        await ethMan.sendTransaction({ to: sbge.address, value: utils.parseEther("2") })
        var postETH = await sbge.daiContribution(ethMan.address)
        console.log("Contribution Successful... New Contribution: " + (postETH/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preETH/10 ** 18).toFixed(2))
        console.log("---------------------------")

        //WETH Contribution Test
        console.log("Mesaj Contributing 2 WETH to SBGE...")
        var preWETH = await sbge.daiContribution(mesaj.address)
        await sbge.connect(mesaj).contributeToken(weth.address, utils.parseEther("2"));
        var postWETH = await sbge.daiContribution(mesaj.address)
        console.log("Contribution Successful... New Contribution: " + (postWETH/10 ** 18).toFixed(2) + " ... Old Contribution: " + (preWETH/10 ** 18).toFixed(2))
        console.log("---------------------------")
        
        // wrap 30k DAI into wDAI
        await wDAI.connect(aTwo).deposit(utils.parseEther("30000"));

        //End SBGE
        await sbge.connect(owner).complete();
        console.log("SBGE COMPLETE")

        //SBGE Contributors claim LP tokens and JCE
        await sbge.connect(aThree).claim();
        console.log("aThree Claims Shares ... New Balance: " + (await JUICEtoken.balanceOf(aThree.address)/10 ** 18).toFixed(2) + " Juice Token and " + (await JCEwdai.balanceOf(aThree.address)/10 ** 18).toFixed(2) + " LP Token")
        await sbge.connect(aFour).claim();
        console.log("aFour Claims Shares ... New Balance: " + (await JUICEtoken.balanceOf(aFour.address)/10 ** 18).toFixed(2) + " Juice Token and " + (await JCEwdai.balanceOf(aFour.address)/10 ** 18).toFixed(2) + " LP Token")
        await sbge.connect(aFive).claim();
        console.log("aFive Claims Shares ... New Balance: " + (await JUICEtoken.balanceOf(aFive.address)/10 ** 18).toFixed(2) + " Juice Token and " + (await JCEwdai.balanceOf(aFive.address)/10 ** 18).toFixed(2) + " LP Token")
        await sbge.connect(ethMan).claim();
        console.log("ethMan Claims Shares ... New Balance: " + (await JUICEtoken.balanceOf(ethMan.address)/10 ** 18).toFixed(2) + " Juice Token and " + (await JCEwdai.balanceOf(ethMan.address)/10 ** 18).toFixed(2) + " LP Token")
        await sbge.connect(mesaj).claim();
        console.log("mesaj Claims Shares ... New Balance: " + (await JUICEtoken.balanceOf(mesaj.address)/10 ** 18).toFixed(2) + " Juice Token and " + (await JCEwdai.balanceOf(mesaj.address)/10 ** 18).toFixed(2) + " LP Token")
  
        //Buy JUICE with wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, JUICEtoken.address], aTwo.address, 2e9);
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, JUICEtoken.address], aTwo.address, 2e9);
        //aTwo sells JUICE for wDAI
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(await JUICEtoken.balanceOf(aTwo.address), 0, [JUICEtoken.address,wDAI.address], aTwo.address, 2e9);
        
        //Buy 10k wDAI worth of JUICE and then send it to aFive
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, JUICEtoken.address], aTwo.address, 2e9);
        await JUICEtoken.connect(aTwo).transfer(aFive.address, await JUICEtoken.balanceOf(aTwo.address))

        //Create JCE-wDAI pool to Vault and init portal params
        await portal.connect(owner).setParameters(owner.address, JuiceVault.address, 100, 10);
        await JuiceVault.connect(owner).addPool(10, JCEwdai.address)
        expect(await JuiceVault.poolInfoCount()).to.equal(1);
        
        //Stake LP tokens to Vault
        await JuiceVault.connect(aThree).deposit(0,await JCEwdai.balanceOf(aThree.address))
        await JuiceVault.connect(aFour).deposit(0,await JCEwdai.balanceOf(aFour.address))
        await JuiceVault.connect(aFive).deposit(0,await JCEwdai.balanceOf(aFive.address))
        await JuiceVault.connect(mesaj).deposit(0,await JCEwdai.balanceOf(mesaj.address))

        //Pending Rewards for LP'ers should be equal at this point with no trades
        expect(await JuiceVault.pendingReward(0,aThree.address)).to.equal(0);

        //Buy JUICE from LP with wDAI and transfer it
        await uniswap.router.connect(aTwo).swapExactTokensForTokensSupportingFeeOnTransferTokens(utils.parseEther("10000"), 0, [wDAI.address, JUICEtoken.address], aTwo.address, 2e9);
        await JUICEtoken.connect(aTwo).transfer(aFive.address, await JUICEtoken.balanceOf(aTwo.address))

        //Test JuiceBook Swap
        await portal.connect(owner).noTax(JuiceBookSwap.address,true)
        await DAItoken.connect(owner).mint(owner.address, utils.parseEther("10000000"))
        console.log("---------------------------")
        console.log("Testing JuiceBook Swap Functionality...")
        console.log("Buying JCE with 10,000 DAI")
        var preCheck = await JUICEtoken.balanceOf(owner.address)
        await JuiceBookSwap.connect(owner).buyJCEwithDAI(utils.parseEther("10000"))
        var postCheck = await JUICEtoken.balanceOf(owner.address)
        console.log("New JCE Balance: " + (postCheck/10 ** 18).toFixed(2) + " Old JCE Balance: " + (preCheck/10 ** 18).toFixed(2))
        console.log("Selling 10,000 JCE For DAI")
        preCheck = await DAItoken.balanceOf(owner.address)
        await JuiceBookSwap.connect(owner).sellJCEforDAI(utils.parseEther("10000"))
        postCheck = await DAItoken.balanceOf(owner.address)
        console.log("New DAI Balance: " + (postCheck/10 ** 18).toFixed(2) + " Old DAI Balance: " + (preCheck/10 ** 18).toFixed(2))
        console.log("---------------------------")

        //Pending rewards for LP'ers should not be 0 after JCE trades have occured
        expect(await JuiceVault.pendingReward(0,aThree.address)).to.not.equal(0);

        // var reward = await JuiceVault.pendingReward(0,aThree.address)
        // console.log("aThree Pending Reward=" + (reward/10 ** 18).toFixed(2))

        // aThree Withdraws from Vault - Should receive Juice Token Reward
        const pre = await JUICEtoken.balanceOf(aThree.address);
        await JuiceVault.connect(aThree).withdraw(0,await JCEwdai.balanceOf(aThree.address)); //should receive some JCE reward when they withdraw
        const post = await JUICEtoken.balanceOf(aThree.address);
        expect(post).to.not.equal(pre);

        // Test Wrapping/Unwrapping DAI <-> wDAI
        var preWrapWDAI = await wDAI.balanceOf(aThree.address)
        var preWrapDAI = await DAItoken.balanceOf(aThree.address)
        await wDAI.connect(aThree).deposit(utils.parseEther('50000'));
        var postWrap = await wDAI.balanceOf(aThree.address)

        expect(preWrapWDAI).to.not.equal(postWrap);
        await wDAI.connect(aThree).withdraw(utils.parseEther('50000'));
        var postUnwrapDAI = await DAItoken.balanceOf(aThree.address)
        expect(preWrapDAI).to.equal(postUnwrapDAI); //DAI balance should be same after wrapping then unwrapping 50k DAI
        await wDAI.connect(aThree).deposit(utils.parseEther('50000'));  //rewrap for liquidity 

        const JCEbalance = await JUICEtoken.balanceOf(JCEwdai.address)
        const WDAIbalance = await wDAI.balanceOf(JCEwdai.address)

        //Check SafeAddLiquidity Function in Transfer Portal
        const check1 = await JCEwdai.balanceOf(aThree.address)
        //Multiply wDAI amt by current JCE price (WDAIbal/JCEbal) to get JCE amt to contribute
        await portal.connect(aThree).safeAddLiquidity(wDAI.address, utils.parseEther(""+50000), utils.parseEther(""+(50000*WDAIbalance/JCEbalance).toFixed(0)),0,0,aThree.address,2e9)
        const check2 = await JCEwdai.balanceOf(aThree.address)
        expect(check1).to.not.equal(check2);
        console.log("Successful liquidity addition through transfer portal... " + ((check2-check1)/10 ** 18).toFixed(2) + " LP Tokens Sent to aThree")

        //Send accessible DAI liquidity to Treasury
        await wDAI.connect(owner).initializeTreasuryBalance(JuiceTreasury.address)
        const final = await DAItoken.balanceOf(JuiceTreasury.address)
        console.log("Final Juice Treasury DAI Token Balance (Funding for Sports Book): "+(final/10 ** 18).toFixed(2) + " DAI")
    }); 
});