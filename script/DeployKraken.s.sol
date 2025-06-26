// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { MockERC20 } from "mocks/MockERC20.sol";

import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { Kraken } from "../src/Kraken.sol";

interface IMockERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

// Fixed constants
address constant INK_POOL_MANAGER = 0x360e68faccca8ca495c1b759fd9eee466db9fb32;
address constant INK_POSITION_MANAGER = 0x1b35d13a2e2528f192637f14b05f0dc0e7deb566;
address constant INK_UNIVERSAL_ROUTER = 0x112908dac86e20e7241b0927479ea3bf935d1fa0;
uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
bytes constant ZERO_BYTES = "";
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @title Deploy Kraken Hook
/// @notice Deployment script for Kraken hook with permissioned pool on INK mainnet
contract DeployKrakenScript is Script {
    IPoolManager public manager = IPoolManager(INK_POOL_MANAGER);
    
    // Declared missing variables
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    PoolSwapTest public swapRouter;
    Kraken public krakenHook;
    
    IMockERC20 public token0;
    IMockERC20 public token1;
    PoolKey public key;

    



    function setUp() public {
        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("Token0", "TK0", 18);
        MockERC20 tokenB = new MockERC20("Token1", "TK1", 18);

        if (address(tokenA) > address(tokenB)) {
            (token0, token1) = (
                Currency.wrap(address(tokenB)),
                Currency.wrap(address(tokenA))
            );
        } else {
            (token0, token1) = (
                Currency.wrap(address(tokenA)),
                Currency.wrap(address(tokenB))
            );
        }

        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        tokenA.mint(msg.sender, 100 * 10 ** 18);
        tokenB.mint(msg.sender, 100 * 10 ** 18);

        key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 120,
            hooks: IHooks(address(0))
        });

        // the second argument here is SQRT_PRICE_1_1
        manager.initialize(key, 79228162514264337593543950336);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Kraken Hook Deployment Script ===");
        console.log("Network: INK Mainnet Fork");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);

        // Connect to existing INK V4 contracts
        manager = PoolManager(payable(INK_POOL_MANAGER));
        modifyLiquidityRouter = manager;
        
        console.log("Using PoolManager at:", address(manager));

        // Deploy test tokens
        deployTestTokens();
        
        // Mine and deploy Kraken hook
        deployKrakenHook();
        
        // Deploy ModifyLiquidityTest if needed (or use existing)
        if (address(modifyLiquidityRouter).code.length == 0) {
            modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
            console.log("PoolModifyLiquidityTest deployed at:", address(modifyLiquidityRouter));
        }
        
        // Initialize pool with hook
        initializePool();
        
        // Add initial liquidity
        addLiquidity();

        vm.stopBroadcast();

        logDeploymentSummary();
    }

    function deployTestTokens() internal {
        console.log("\n=== Deploying Test Tokens ===");
        
        // Deploy simple mock tokens
        token0 = IMockERC20(address(new MockERC20("Mock USDC", "mUSDC", 6)));
        token1 = IMockERC20(address(new MockERC20("Mock ETH", "mETH", 18)));
        
        // Mint tokens to deployer
        token0.mint(msg.sender, 1000000 * 10**6); // 1M mUSDC
        token1.mint(msg.sender, 1000 * 10**18);   // 1K mETH
        
        // Ensure proper ordering for V4
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        
        console.log("Token0 (", token0.symbol(), ") deployed at:", address(token0));
        console.log("Token1 (", token1.symbol(), ") deployed at:", address(token1));
    }

    function deployKrakenHook() internal {
        console.log("\n=== Mining and Deploying Kraken Hook ===");
        
        // Determine hook flags
        uint160 flags = uint160(
            uint256(1 << 128) // BEFORE_SWAP_FLAG
        );
        
        console.log("Required hook flags:", flags);
        
        // Constructor arguments
        bytes memory constructorArgs = abi.encode(address(manager));
        
        // Mine hook address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(Kraken).creationCode,
            constructorArgs
        );
        
        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        
        // Deploy hook
        krakenHook = new Kraken{salt: salt}(IPoolManager(manager));
        
        require(address(krakenHook) == hookAddress, "Hook address mismatch");
        console.log("Kraken Hook deployed at:", address(krakenHook));
    }

    function initializePool() internal {
        console.log("\n=== Initializing Pool ===");
        
        // Initialize pool using Deployers helper
        (key, ) = initPool(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            address(0),
            3000, // 0.3% fee
            SQRT_PRICE_1_1 // 1:1 price
        );
        
        console.log("Pool initialized:");
        console.log("  Currency0:", Currency.unwrap(key.currency0));
        console.log("  Currency1:", Currency.unwrap(key.currency1));
        console.log("  Fee:", key.fee);
        console.log("  Hook:", address(key.hooks));
    }

    function addLiquidity() internal {
        console.log("\n=== Adding Liquidity ===");
        
        // Approve tokens
        uint256 token0Amount = 100000 * 10**token0.decimals();
        uint256 token1Amount = 100 * 10**token1.decimals();
        
        token0.approve(address(modifyLiquidityRouter), token0Amount);
        token1.approve(address(modifyLiquidityRouter), token1Amount);
        
        // Use correct parameter struct
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1000000,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        
        console.log("Liquidity added successfully");
    }

    function logDeploymentSummary() internal view {
        console.log("\n==================================================");
        console.log("           DEPLOYMENT SUMMARY");
        console.log("==================================================");
        console.log("Network: INK Mainnet Fork (Chain ID: 57073)");
        console.log("");
        console.log("V4 Infrastructure:");
        console.log("  PoolManager:      ", INK_POOL_MANAGER);
        console.log("  PositionManager:  ", INK_POSITION_MANAGER);
        console.log("  Universal Router: ", INK_UNIVERSAL_ROUTER);
        console.log("");
        console.log("Kraken Hook:      ", address(krakenHook));
        console.log("");
        console.log("Test Tokens:");
        console.log("  Token0 (", token0.symbol(), "):      ", address(token0));
        console.log("  Token1 (", token1.symbol(), "):       ", address(token1));
        console.log("");
        console.log("Pool:");
        console.log("  Currency0:    ", Currency.unwrap(key.currency0));
        console.log("  Currency1:    ", Currency.unwrap(key.currency1));
        console.log("  Fee:          ", key.fee);
        console.log("  Hook:         ", address(key.hooks));
        console.log("");
        console.log("Deployment Complete!");
        console.log("==================================================");
    }
} 