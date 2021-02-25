pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

/*
It:
    Allows customization of tax and burn rates
    Allows transfer to/from approved Uniswap pools
    Disallows transfer to/from non-approved Uniswap pools
    (doesn't interfere with other crappy AMMs)
    Allows transfer to/from anywhere else
    Allows for free transfers if permission granted
    Allows for unrestricted transfers if permission granted
    Provides a safe and tax-free liquidity adding function
*/

import "./interfaces/ITransferPortal.sol";
import "./interfaces/IERC20.sol";
import "./uniswap/IUniswapV2Pair.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapV2Factory.sol";
import "./BookToken.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

//Scaled up by 100 - 10000 = 100%
struct BOOKTransferPortalParameters{
    address dev;
    uint16 devRewardRate;
    uint16 vaultRewardRate;
    address vault;
}

contract TransferPortal is ITransferPortal{   
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address owner;

    enum AddressState{
        Unknown,
        NotPool,
        DisallowedPool,
        AllowedPool
    }

    modifier ownerOnly(){
        require (msg.sender == owner, "Owner only");
        _;
    }

    BOOKTransferPortalParameters public parameters;
    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;
    BookToken immutable BOOK;

    mapping (address => AddressState) public addressStates;
    IERC20[] public allowedPoolTokens;
    
    bool public unrestricted;
    mapping (address => bool) public unrestrictedControllers;
    mapping (address => bool) public freeParticipant;

    mapping (address => uint256) public liquiditySupply;
    address public mustUpdate;    

    constructor(BookToken _BOOK, IUniswapV2Router02 _uniswapV2Router){
    // constructor(BookToken _BOOK){
        owner = msg.sender;
        BOOK = _BOOK;
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
    }

    function allowedPoolTokensCount() public view returns (uint256) { return allowedPoolTokens.length; }

    function setUnrestrictedController(address unrestrictedController, bool allow) public ownerOnly(){
        unrestrictedControllers[unrestrictedController] = allow;
    }

    function setFreeParticipant(address participant, bool free) public ownerOnly(){
        freeParticipant[participant] = free;
    }

    function setUnrestricted(bool _unrestricted) public {
        require (unrestrictedControllers[msg.sender], "Not an unrestricted controller");
        unrestricted = _unrestricted;
    }

    function setParameters(address _dev, address _vault, uint16 _vaultRewardRate, uint16 _devRate) public ownerOnly(){
        require (_dev != address(0) && _vault != address(0));
        require (_vaultRewardRate <= 500 && _devRate <= 10, "Sanity");
        
        BOOKTransferPortalParameters memory _parameters;
        _parameters.dev = _dev;
        _parameters.vaultRewardRate = _vaultRewardRate;
        _parameters.devRewardRate = _devRate;
        _parameters.vault = _vault;
        parameters = _parameters;
    }

    function allowPool(IERC20 token) public ownerOnly(){
        address pool = uniswapV2Factory.getPair(address(BOOK), address(token));
        if (pool == address(0)) {
            pool = uniswapV2Factory.createPair(address(BOOK), address(token));
        }
        AddressState state = addressStates[pool];
        require (state != AddressState.AllowedPool, "Already allowed");
        addressStates[pool] = AddressState.AllowedPool;
        allowedPoolTokens.push(token);
        liquiditySupply[pool] = IERC20(pool).totalSupply();
    }

    function safeAddLiquidity(IERC20 token, uint256 tokenAmount, uint256 bookAmount, uint256 minTokenAmount, uint256 minBookAmount, address to, uint256 deadline) public
    returns (uint256 bookUsed, uint256 tokenUsed, uint256 liquidity){
        address pool = uniswapV2Factory.getPair(address(BOOK), address(token));
        require (pool != address(0) && addressStates[pool] == AddressState.AllowedPool, "Pool not approved");
        unrestricted = true;

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        BOOK.transferFrom(msg.sender, address(this), bookAmount);
        BOOK.approve(address(uniswapV2Router), bookAmount);
        token.safeApprove(address(uniswapV2Router), tokenAmount);
        (bookUsed, tokenUsed, liquidity) = uniswapV2Router.addLiquidity(address(BOOK), address(token), bookAmount, tokenAmount, minBookAmount, minTokenAmount, to, deadline);
        liquiditySupply[pool] = IERC20(pool).totalSupply();
        if (mustUpdate == pool) {
            mustUpdate = address(0);
        }

        if (bookUsed < bookAmount) {
            BOOK.transfer(msg.sender, bookAmount - bookUsed);
        }
        tokenBalance = token.balanceOf(address(this)).sub(tokenBalance);
        if (tokenBalance > 0) {
            token.safeTransfer(msg.sender, tokenBalance);
        }
        
        unrestricted = false;
    }

    function handleTransfer(address, address from, address to, uint256 amount) external override
        returns (TransferPortalTarget[] memory targets){

        address mustUpdateAddress = mustUpdate;
        if (mustUpdateAddress != address(0)) {
            mustUpdate = address(0);
            liquiditySupply[mustUpdateAddress] = IERC20(mustUpdateAddress).totalSupply();
        }
        AddressState fromState = addressStates[from];
        AddressState toState = addressStates[to];

        if (fromState != AddressState.AllowedPool && toState != AddressState.AllowedPool) {
            if (fromState == AddressState.Unknown) { fromState = detectState(from); }
            if (toState == AddressState.Unknown) { toState = detectState(to); }
            require (unrestricted || (fromState != AddressState.DisallowedPool && toState != AddressState.DisallowedPool), "Pool not approved");
        }
        if (toState == AddressState.AllowedPool) {
            mustUpdate = to;
        }
        if (fromState == AddressState.AllowedPool) {
            if (unrestricted) {
                liquiditySupply[from] = IERC20(from).totalSupply();
            }
            require (IERC20(from).totalSupply() >= liquiditySupply[from], "Cannot remove liquidity");            
        }
        if (unrestricted || freeParticipant[from]) {
            return new TransferPortalTarget[](0);
        }
        BOOKTransferPortalParameters memory params = parameters;


        // burn = amount * params.burnRate / 10000;
        targets = new TransferPortalTarget[]((params.devRewardRate > 0 ? 1 : 0) + (params.vaultRewardRate > 0 ? 1 : 0));
        uint256 index = 0;
        if (params.vaultRewardRate > 0) {
            targets[index].destination = params.vault;
            targets[index++].amount = amount * params.vaultRewardRate / 10000;
        }
        if (params.devRewardRate > 0) {
            targets[index].destination = params.dev;
            targets[index].amount = amount * params.devRewardRate / 10000;
        }
    }

    function setAddressState(address a, AddressState state) public ownerOnly(){
        addressStates[a] = state;
    }

    function detectState(address a) public returns (AddressState state) {
        state = AddressState.NotPool;
        if (a.isContract()) {
            try this.throwAddressState(a){
                assert(false);
            }
            catch Error(string memory result) {
                if (bytes(result).length == 2) {
                    state = AddressState.DisallowedPool;
                }
            }
            catch {
            }
        }
        addressStates[a] = state;
        return state;
    }
    
    // Not intended for external consumption
    // Always throws
    // We want to call functions to probe for things, but don't want to open ourselves up to
    // possible state-changes
    // So we return a value by reverting with a message
    function throwAddressState(address a) external view{
        try IUniswapV2Pair(a).factory() returns (address factory)
        {
            // don't care if it's some crappy alt-amm
            if (factory == address(uniswapV2Factory)) {
                // these checks for token0/token1 are just for additional
                // certainty that we're interacting with a uniswap pair
                try IUniswapV2Pair(a).token0() returns (address token0)
                {
                    if (token0 == address(BOOK)) {
                        revert("22");
                    }
                    try IUniswapV2Pair(a).token1() returns (address token1)
                    {
                        if (token1 == address(BOOK)) {
                            revert("22");
                        }                        
                    }
                    catch { 
                    }                    
                }
                catch { 
                }
            }
        }
        catch {             
        }
        revert("1");
    }
}