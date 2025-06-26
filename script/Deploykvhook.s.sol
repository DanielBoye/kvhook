// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { ProxyPoolManager } from "@uniswap/v4-core/src/test/ProxyPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { kvhook } from "../src/kvhook.sol";

// Robust CREATE2 factory inspired by OpenZeppelin's approach
contract Create2Factory {
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt);
    
    /**
     * @dev Computes the address of a contract that would be deployed with CREATE2
     * @param salt The salt used for CREATE2 deployment
     * @param creationCode The creation code of the contract
     * @return The computed address
     */
    function computeAddress(bytes32 salt, bytes memory creationCode) public view returns (address) {
        return address(uint160(uint256(keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(creationCode)
            )
        ))));
    }
    
    /**
     * @dev Deploys a contract using CREATE2
     * @param salt The salt for CREATE2 deployment
     * @param creationCode The creation code of the contract to deploy
     * @return deployed The address of the deployed contract
     */
    function deploy(bytes32 salt, bytes memory creationCode) external returns (address deployed) {
        // Compute expected address
        address expectedAddress = computeAddress(salt, creationCode);
        
        // Deploy using CREATE2
        assembly {
            deployed := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        
        require(deployed != address(0), "Create2Factory: Failed to deploy");
        require(deployed == expectedAddress, "Create2Factory: Address mismatch");
        
        emit ContractDeployed(deployed, salt);
        return deployed;
    }
}

contract DeploykvhookScript is Script {
    PoolManager public manager;
    Create2Factory public create2Factory;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    kvhook public krakenHook;
    MockERC20 public token0;
    MockERC20 public token1;
    PoolKey public key;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying Kraken Hook to INK Sepolia ===");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CREATE2 factory first
        create2Factory = new Create2Factory();
        console.log("CREATE2 Factory:", address(create2Factory));
        
        // Deploy PoolManager
        manager = new PoolManager(deployer);
        console.log("PoolManager:", address(manager));
        
        // Deploy test tokens
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(deployer, 1000000 * 10**18);
        token1.mint(deployer, 1000 * 10**18);
        
        // Prepare hook creation code
        bytes memory hookCreationCode = abi.encodePacked(
            type(kvhook).creationCode,
            abi.encode(manager)
        );
        
        // Mine salt for proper hook address (with BEFORE_SWAP_FLAG)
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        (address expectedHookAddress, bytes32 salt) = HookMiner.find(
            address(create2Factory),
            flags,
            type(kvhook).creationCode,
            abi.encode(manager)
        );
        
        console.log("Expected Hook Address:", expectedHookAddress);
        console.log("Salt:", vm.toString(salt));
        
        // Verify the computed address matches
        address computedAddress = create2Factory.computeAddress(salt, hookCreationCode);
        require(computedAddress == expectedHookAddress, "Address computation mismatch");
        
        // Deploy the hook using CREATE2
        address deployedHookAddress = create2Factory.deploy(salt, hookCreationCode);
        krakenHook = kvhook(deployedHookAddress);
        
        console.log("Deployed Hook Address:", address(krakenHook));
        require(address(krakenHook) == expectedHookAddress, "Hook deployment address mismatch");

        address token0Addr = address(token0);
        address token1Addr = address(token1);

        // Sort token addresses numerically
        (address sortedToken0, address sortedToken1) = token0Addr < token1Addr 
            ? (token0Addr, token1Addr) 
            : (token1Addr, token0Addr);

        
        // Initialize pool
        key = PoolKey({
            currency0: Currency.wrap(sortedToken0),
            currency1: Currency.wrap(sortedToken1),
            fee: 3000,
            tickSpacing: 120,
            hooks: IHooks(address(krakenHook))
        });
        manager.initialize(key, 79228162514264337593543950336);
        
        // Deploy liquidity router
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        
        // Add liquidity
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10e18,
                salt: 0
            }),
            new bytes(0)
        );
        
        vm.stopBroadcast();
        
        console.log("Deployment Summary:");
        console.log("CREATE2 Factory:", address(create2Factory));
        console.log("PoolManager:", address(manager));
        console.log("Kraken Hook:", address(krakenHook));
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));
        console.log("Liquidity Router:", address(modifyLiquidityRouter));
    }
}