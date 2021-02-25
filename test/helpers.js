const { ethers } = require("hardhat");
const { utils, constants } = require("ethers");

const UniswapV2PairJson = require('../contracts/json/UniswapV2Pair.json');
const UniswapV2FactoryJson = require('../contracts/json/UniswapV2Factory.json');
const UniswapV2Router02Json = require('../contracts/json/UniswapV2Router02.json');
const UniswapV2LibraryJson = require('../contracts/json/UniswapV2Library.json');

exports.createWETH = async function() {
    const wethFactory = await ethers.getContractFactory("WETH9");
    return await wethFactory.deploy();
}

exports.createUniswap = async function(owner, weth) {
    const amt = utils.parseEther("100");
    const daiamt = utils.parseEther("150000");
    const daiamt2 = utils.parseEther("5000000");

    const erc20Factory = await ethers.getContractFactory("ERC20Test");
    const daiFactory = await ethers.getContractFactory("Dai");
    const wbtc = await erc20Factory.connect(owner).deploy();
    const dai = await daiFactory.connect(owner).deploy();
    await dai.connect(owner).mint(owner.address, daiamt);
    await dai.connect(owner).mint(owner.address, daiamt);
    await dai.connect(owner).mint(owner.address, daiamt2);
    const factory = await new ethers.ContractFactory(UniswapV2FactoryJson.abi, UniswapV2FactoryJson.bytecode, owner).deploy(owner.address);
    const router = await new ethers.ContractFactory(UniswapV2Router02Json.abi, UniswapV2Router02Json.bytecode, owner).deploy(factory.address, weth.address);
    const library = await new ethers.ContractFactory(UniswapV2LibraryJson.abi, UniswapV2LibraryJson.bytecode, owner).deploy();

    await owner.sendTransaction({ to: weth.address, value: amt });
    await weth.connect(owner).approve(router.address, constants.MaxUint256);
    await wbtc.connect(owner).approve(router.address, constants.MaxUint256);
    await dai.connect(owner).approve(router.address, constants.MaxUint256);
    await router.connect(owner).addLiquidity(wbtc.address, weth.address, amt, amt, amt, amt, owner.address, 2e9);
    // console.log("TestWBTC="+wbtc.address)
    // console.log("TestWETH="+weth.address)
    // console.log("TestDAI="+dai.address)
    // console.log("Test="+await factory.connect(owner).getPair(wbtc.address,weth.address))
    await owner.sendTransaction({ to: weth.address, value: amt });
    await router.connect(owner).addLiquidity(weth.address,dai.address, amt, daiamt, amt, daiamt, owner.address, 2e9);

    await owner.sendTransaction({ to: weth.address, value: amt });
    // console.log("Test DAI/WETH LP ADDR="+ await factory.connect(owner).getPair(dai.address,weth.address))

    await router.connect(owner).addLiquidity(wbtc.address,dai.address, amt, daiamt2, amt, daiamt2, owner.address, 2e9);

    // console.log("Test DAI/WBTC LP ADDR="+ await factory.connect(owner).getPair(dai.address,wbtc.address))
    return {
        factory,
        router,
        library,
        wbtc,
        dai,
        pairFor: address => new ethers.Contract(address, UniswapV2PairJson.abi, owner)
    };
}