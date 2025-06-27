#!/bin/bash

# Script to interact with the deployed Kraken hook and test authorization
# Usage: ./interact.sh

set -e

echo "🔑 Loading environment variables..."
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "Please run extract-addresses.sh first to create .env file"
    exit 1
fi

source .env

# Verify required environment variables
required_vars=(
    "PRIVATE_KEY"
    "POOL_MANAGER_ADDRESS" 
    "HOOK_ADDRESS"
    "TOKEN0_ADDRESS"
    "TOKEN1_ADDRESS"
    "POOL_SWAP_TEST_ADDRESS"
    "POOL_MODIFY_LIQUIDITY_TEST_ADDRESS"
)

echo "🔍 Checking required environment variables..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: $var not found in .env file"
        exit 1
    fi
    if [ "$var" == "PRIVATE_KEY" ]; then
        echo "✅ $var: [***]"
    else
        echo "✅ $var: ${!var}"
    fi
done

echo ""
echo "🏊 Setting up pool interaction..."

# Extract wallet address from private key
WALLET_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
echo "📧 Wallet Address: $WALLET_ADDRESS"

echo ""
echo "💰 Checking token balances..."

# Check Token0 balance
TOKEN0_BALANCE=$(cast call $TOKEN0_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url https://rpc-gel-sepolia.inkonchain.com)
TOKEN0_BALANCE_DEC=$(cast --to-dec $TOKEN0_BALANCE 2>/dev/null || echo $TOKEN0_BALANCE)
echo "🪙 Token0 Balance: $TOKEN0_BALANCE_DEC"

# Check Token1 balance  
TOKEN1_BALANCE=$(cast call $TOKEN1_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url https://rpc-gel-sepolia.inkonchain.com)
TOKEN1_BALANCE_DEC=$(cast --to-dec $TOKEN1_BALANCE 2>/dev/null || echo $TOKEN1_BALANCE)
echo "🪙 Token1 Balance: $TOKEN1_BALANCE_DEC"

echo ""
echo "🔓 Approving tokens for PoolSwapTest..."

# Approve Token0 for PoolSwapTest
echo "Approving Token0..."
cast send $TOKEN0_ADDRESS \
    "approve(address,uint256)" \
    $POOL_SWAP_TEST_ADDRESS \
    1000000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url https://rpc-gel-sepolia.inkonchain.com

# Approve Token1 for PoolSwapTest
echo "Approving Token1..."
cast send $TOKEN1_ADDRESS \
    "approve(address,uint256)" \
    $POOL_SWAP_TEST_ADDRESS \
    1000000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url https://rpc-gel-sepolia.inkonchain.com

echo ""
echo "🏊 Creating pool if it doesn't exist..."

# Create pool key struct data
# PoolKey: currency0, currency1, fee, tickSpacing, hooks
POOL_KEY_DATA=$(cast abi-encode \
    "f(address,address,uint24,int24,address)" \
    $TOKEN0_ADDRESS \
    $TOKEN1_ADDRESS \
    $POOL_FEE \
    $TICK_SPACING \
    $HOOK_ADDRESS)

echo "Pool Key Data: $POOL_KEY_DATA"

# Try to initialize the pool (this may fail if already initialized, which is OK)
echo "🔄 Attempting to initialize pool..."
INIT_RESULT=$(cast send $POOL_MODIFY_LIQUIDITY_TEST_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url https://rpc-gel-sepolia.inkonchain.com \
    --gas-limit 3000000 \
    "initializePool((address,address,uint24,int24,address),uint160)" \
    "($TOKEN0_ADDRESS,$TOKEN1_ADDRESS,$POOL_FEE,$TICK_SPACING,$HOOK_ADDRESS)" \
    79228162514264337593543950336 2>&1)

if echo "$INIT_RESULT" | grep -q "status.*1 (success)" || echo "$INIT_RESULT" | grep -q "blockHash"; then
    echo "✅ Pool initialized successfully"
else
    echo "⚠️  Pool initialization failed (might already be initialized)"
fi

echo ""
echo "💧 Adding initial liquidity..."

# Add liquidity to the pool
cast send $POOL_MODIFY_LIQUIDITY_TEST_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url https://rpc-gel-sepolia.inkonchain.com \
    --gas-limit 3000000 \
    "modifyLiquidity((address,address,uint24,int24,address),int24,int24,int256,bytes)" \
    "($TOKEN0_ADDRESS,$TOKEN1_ADDRESS,$POOL_FEE,$TICK_SPACING,$HOOK_ADDRESS)" \
    -- -600 \
    600 \
    1000000000000000000 \
    "0x" || echo "⚠️  Liquidity addition failed"

echo ""
echo "🔄 Testing swap with Kraken hook authorization..."

# Perform a swap that will trigger the beforeSwap hook
echo "🚀 Executing swap to test Kraken hook..."
echo "This will test if the wallet address has proper attestation..."

# Swap parameters: zeroForOne=true, amountSpecified=-100000000000000000 (0.1 token), sqrtPriceLimitX96=0
SWAP_RESULT=$(cast send $POOL_SWAP_TEST_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url https://rpc-gel-sepolia.inkonchain.com \
    --gas-limit 3000000 \
    "swap((address,address,uint24,int24,address),bool,int256,uint160,bytes)" \
    "($TOKEN0_ADDRESS,$TOKEN1_ADDRESS,$POOL_FEE,$TICK_SPACING,$HOOK_ADDRESS)" \
    true \
    -- -100000000000000000 \
    0 \
    "0x" 2>&1)

echo "$SWAP_RESULT"

if echo "$SWAP_RESULT" | grep -q "Transaction successful" || echo "$SWAP_RESULT" | grep -q "blockHash"; then
    echo ""
    echo "🎉 SUCCESS! Swap completed successfully!"
    echo "✅ The Kraken hook authorized the transaction"
    echo "✅ Your wallet address ($WALLET_ADDRESS) has valid attestation"
    
    echo ""
    echo "💰 Updated token balances:"
    # Check updated balances
    TOKEN0_BALANCE_NEW=$(cast call $TOKEN0_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url https://rpc-gel-sepolia.inkonchain.com)
    TOKEN0_BALANCE_NEW_DEC=$(cast --to-dec $TOKEN0_BALANCE_NEW 2>/dev/null || echo $TOKEN0_BALANCE_NEW)
    echo "🪙 Token0 Balance: $TOKEN0_BALANCE_NEW_DEC"
    
    TOKEN1_BALANCE_NEW=$(cast call $TOKEN1_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url https://rpc-gel-sepolia.inkonchain.com)
    TOKEN1_BALANCE_NEW_DEC=$(cast --to-dec $TOKEN1_BALANCE_NEW 2>/dev/null || echo $TOKEN1_BALANCE_NEW)
    echo "🪙 Token1 Balance: $TOKEN1_BALANCE_NEW_DEC"
    
else
    echo ""
    echo "❌ SWAP FAILED!"
    if echo "$SWAP_RESULT" | grep -q "AttestationNotFound\|AttestationExpired\|AttestationRevoked"; then
        echo "🔒 Authorization failed: Your wallet address does not have valid attestation"
        echo "📋 Wallet Address: $WALLET_ADDRESS"
        echo "🔑 Required Schema UID: 0x8ffa68bde25f7b88e042ea3dff55ff27217b7d1c4bf24f57967b285c5ffe4c8b"
        echo ""
        echo "💡 To fix this:"
        echo "1. Get a valid attestation for your wallet address"
        echo "2. Ensure the attestation uses the correct schema UID"
        echo "3. Make sure the attestation is not expired or revoked"
    else
        echo "🔍 Error details:"
        echo "$SWAP_RESULT"
    fi
fi

echo ""
echo "📋 Interaction Summary:"
echo "  - Hook Address: $HOOK_ADDRESS"
echo "  - Wallet Address: $WALLET_ADDRESS"  
echo "  - Pool: $TOKEN0_ADDRESS / $TOKEN1_ADDRESS"
echo "  - Pool Fee: $POOL_FEE"
echo "  - Network: INK Sepolia (Chain ID: $CHAIN_ID)"
echo ""
echo "🔗 Explorer: https://explorer-sepolia.inkonchain.com/address/$HOOK_ADDRESS" 