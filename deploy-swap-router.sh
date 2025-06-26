#!/bin/bash

# Deploy PoolSwapTest router to interact with the pool
echo "🔑 Loading environment variables..."
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    exit 1
fi

source .env

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not found in .env file"
    exit 1
fi

echo "🚀 Deploying PoolSwapTest router..."
# Capture the deployment output
DEPLOY_OUTPUT=$(forge script --rpc-url https://rpc-gel-sepolia.inkonchain.com \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvv \
    --sig "run(address)" \
    lib/uniswap-hooks/lib/v4-periphery/script/03_PoolSwapTest.s.sol:DeployPoolSwapTest \
    $POOL_MANAGER_ADDRESS 2>&1)

echo "$DEPLOY_OUTPUT"

# Extract PoolSwapTest address from deployment output
echo "🔍 Extracting PoolSwapTest address from deployment output..."

# Extract the contract address from DEPLOY_OUTPUT
POOL_SWAP_TEST_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -Eo '0x[a-fA-F0-9]{40}' | head -1)

# Validate that we extracted an address
if [ -z "$POOL_SWAP_TEST_ADDRESS" ]; then
    echo "❌ Error: Could not extract PoolSwapTest address from deployment output"
    echo "🔍 Deployment output:"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

echo "📝 Extracted address: $POOL_SWAP_TEST_ADDRESS"

# Add or update the variable in the .env file
if grep -q '^POOL_SWAP_TEST_ADDRESS=' .env; then
    echo "📝 Updating existing POOL_SWAP_TEST_ADDRESS in .env"
    sed -i "s/^POOL_SWAP_TEST_ADDRESS=.*/POOL_SWAP_TEST_ADDRESS=$POOL_SWAP_TEST_ADDRESS/" .env
else
    echo "📝 Adding new POOL_SWAP_TEST_ADDRESS to .env"
    echo "POOL_SWAP_TEST_ADDRESS=$POOL_SWAP_TEST_ADDRESS" >> .env
fi

echo "✅ PoolSwapTest deployment complete!"
echo "📋 PoolSwapTest Address: $(grep POOL_SWAP_TEST_ADDRESS .env | tail -1 | cut -d'=' -f2)" 

