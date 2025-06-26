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

/**
 * @title kvhook
 * @notice Restricts swaps to users with valid Kraken attestations
 * @dev Inherits from BaseHook and KrakenVerifyAccessControl
 * @dev UID of the verified kraken user schema
 * @dev Must match Kraken's attestation schema
 * @dev Error thrown when user is not authorized
 */
contract kvhook is BaseHook, KrakenVerifyAccessControl {
    bytes32 private constant VERIFIED_SCHEMA_UID = 0x8ffa68bde25f7b88e042ea3dff55ff27217b7d1c4bf24f57967b285c5ffe4c8b;

    /// @dev Error thrown when user is not authorized
    error Unauthorized();
    /**
     * @notice Constructor that initializes the hook with the pool manager
     * @param _poolManager The pool manager contract
     */
    constructor(IPoolManager _poolManager)
        BaseHook(_poolManager)
    {}

    /**
     * @notice Specifies enabled Uniswap V4 hook callbacks
     * @dev Only beforeSwap is enabled to gate user access
     * @return permissions Struct with hook permissions configuration
     */
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

    /**
     * @notice Verifies user attestation status
     * @dev Reverts with specific errors on verification failure
     * @param sender User address to verify
     * @return true Always returns true on successful verification
     * @custom:error AttestationNotFound
     * @custom:error AttestationExpired
     * @custom:error AttestationRevoked
     * @custom:error AttestationRecipientMismatch
     * @custom:error AttestationSchemaMismatch
     * @custom:error AttestationInvariantViolation
     */
    function _verifyAndCheckSender(address sender) internal returns (bool) {
        Attestation memory attestation = _getAttestation(
            sender,
            VERIFIED_SCHEMA_UID
        );
        
        AttestationVerifier.verifyAttestation(
            attestation,
            sender,
            VERIFIED_SCHEMA_UID
        );

        return true;
    }

    /**
     * @notice Hook executed before swap operations
     * @dev Reverts transaction if user lacks valid attestation
     * @param sender Transaction initiator address
     * @param key Pool identifier
     * @param swapParams Swap parameters
     * @return selector Function selector for hook compliance
     * @return swapDelta Required swap delta (always zero)
     * @return swapFee Fee override (always 0 = use pool default)
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!_verifyAndCheckSender(sender)) {
            revert Unauthorized();
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
