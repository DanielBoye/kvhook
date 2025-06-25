// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { KrakenVerifyAccessControl } from "@krakenfx/verify/src/abstracts/KrakenVerifyAccessControl.sol";

import { BaseHook } from "uniswap-hooks/base/BaseHook.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPoolManager, SwapParams } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { BeforeSwapDelta, BeforeSwapDeltaLibrary } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { Attestation, AttestationVerifier } from "@krakenfx/verify/src/libraries/AttestationVerifier.sol";
import { 
    AttestationNotFound, 
    AttestationExpired, 
    AttestationRevoked, 
    AttestationRecipientMismatch, 
    AttestationSchemaMismatch, 
    AttestationInvariantViolation 
} from "@krakenfx/verify/src/libraries/AttestationErrors.sol";

contract Kraken is BaseHook, KrakenVerifyAccessControl {
    /// @notice Cache of verified users to save gas
    mapping(address => bool) public preVerified;

    /// @dev UID of the verified kraken user schema
    bytes32 private constant VERIFIED_SCHEMA_UID = 0x8ffa68bde25f7b88e042ea3dff55ff27217b7d1c4bf24f57967b285c5ffe4c8b;

    constructor(IPoolManager _poolManager)
        BaseHook(_poolManager)
    {}

    /// @notice Specifies which Uniswap V4 hook callbacks are enabled
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _verifyAndCheckSender(address sender) internal returns (bool) {
        // Check if already pre-verified to save gas
        // if (preVerified[sender]) {
        //     return;
        // }

        Attestation memory attestation = _getAttestation(
            sender,
            VERIFIED_SCHEMA_UID
        );
        
        AttestationVerifier.verifyAttestation(
            attestation,
            sender,
            VERIFIED_SCHEMA_UID
        );

        preVerified[sender] = true;

        return true;
    }

    /// @notice Callback executed before a swap
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        _verifyAndCheckSender(sender);

        // do something

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
