#!/bin/bash

# Script to extract contract addresses from deployment JSON and save to .env

JSON_FILE="broadcast/Deploykvhook.s.sol/763373/run-latest.json"
ENV_FILE=".env"

echo "🔍 Extracting contract addresses from deployment..."

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "❌ Error: $JSON_FILE not found!"
    exit 1
fi

# Add header to .env file (append mode)
cat >> "$ENV_FILE" << EOF

# Contract Addresses - Extracted from deployment
# Chain: INK Sepolia (763373)
# Deployment: $(date)

EOF

# Extract addresses using jq and format for .env
echo "📝 Writing addresses to $ENV_FILE..."

# Helper function to extract contract address by name
extract_address() {
    local contract_name="$1"
    local var_name="$2"
    
    address=$(jq -r --arg name "$contract_name" '
        .transactions[] | 
        select(.contractName == $name and .contractAddress != null) | 
        .contractAddress
    ' "$JSON_FILE" | head -1)
    
    if [ "$address" != "null" ] && [ -n "$address" ]; then
        echo "${var_name}=${address}" >> "$ENV_FILE"
        echo "✅ $contract_name: $address"
    else
        echo "⚠️  $contract_name: Not found"
    fi
}

# Extract specific contracts
extract_address "Create2Factory" "CREATE2_FACTORY_ADDRESS"
extract_address "PoolManager" "POOL_MANAGER_ADDRESS" 

# Extract Hook address from CREATE2 deployment in additionalContracts
hook_address=$(jq -r '
    .transactions[] | 
    select(.contractName == "Create2Factory" and .function == "deploy(bytes32,bytes)") |
    .additionalContracts[]? |
    select(.transactionType == "CREATE2") |
    .address
' "$JSON_FILE")

if [ "$hook_address" != "null" ] && [ -n "$hook_address" ]; then
    echo "HOOK_ADDRESS=${hook_address}" >> "$ENV_FILE"
    echo "✅ Hook Contract: $hook_address"
else
    echo "⚠️  Hook Contract: Not found"
fi

# Extract MockERC20 tokens by arguments (Token0, Token1)
token0_address=$(jq -r '
    .transactions[] | 
    select(.contractName == "MockERC20" and .arguments[0] == "Token0") | 
    .contractAddress
' "$JSON_FILE")

token1_address=$(jq -r '
    .transactions[] | 
    select(.contractName == "MockERC20" and .arguments[0] == "Token1") | 
    .contractAddress
' "$JSON_FILE")

if [ "$token0_address" != "null" ] && [ -n "$token0_address" ]; then
    echo "TOKEN0_ADDRESS=${token0_address}" >> "$ENV_FILE"
    echo "✅ Token0 (TK0): $token0_address"
else
    echo "⚠️  Token0: Not found"
fi

if [ "$token1_address" != "null" ] && [ -n "$token1_address" ]; then
    echo "TOKEN1_ADDRESS=${token1_address}" >> "$ENV_FILE"
    echo "✅ Token1 (TK1): $token1_address"
else
    echo "⚠️  Token1: Not found"
fi

# Extract PoolModifyLiquidityTest address
extract_address "PoolModifyLiquidityTest" "POOL_MODIFY_LIQUIDITY_TEST_ADDRESS"

# Add network info
cat >> "$ENV_FILE" << EOF

# Network Configuration
CHAIN_ID=763373
RPC_URL=https://rpc-gel-sepolia.inkonchain.com
EXPLORER_URL=https://explorer-sepolia.inkonchain.com

# Pool Configuration  
POOL_FEE=3000
TICK_SPACING=120

EOF

echo ""
echo "🎉 Contract addresses successfully extracted to $ENV_FILE"
echo ""
echo "📋 Summary:"
echo "  - Create2Factory: $(grep CREATE2_FACTORY_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"
echo "  - PoolManager: $(grep POOL_MANAGER_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"  
echo "  - Hook Contract: $(grep HOOK_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"
echo "  - Token0 (TK0): $(grep TOKEN0_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"
echo "  - Token1 (TK1): $(grep TOKEN1_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"
echo "  - PoolModifyLiquidityTest: $(grep POOL_MODIFY_LIQUIDITY_TEST_ADDRESS "$ENV_FILE" | cut -d'=' -f2)"
echo ""
echo "🔑 Loading environment variables..."
source .env
echo "✅ Environment variables loaded successfully"
echo "📋 Contract addresses are now available in .env file"
