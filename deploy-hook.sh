#!/bin/bash

set -e

echo "⛏️  Compiling contracts..."
forge build

echo "🔑 Loading environment variables..."
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    exit 1
fi

source .env
echo "🚀 Deploying kvhook..."
forge script script/Deploykvhook.s.sol:DeploykvhookScript \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvv

if [ $? -eq 0 ]; then
    echo "✅ Deployment complete!"
    echo ""
    echo "🎯 Next steps:"
    echo "1. The Kraken hook is now deployed and integrated with INK mainnet V4 contracts"
    echo "2. Use the test tokens and routers for testing"
    echo "3. Set up user attestations in the hook"
    echo "4. Test swaps to verify hook functionality"
    echo ""
else
    echo "❌ Deployment failed"
    exit 1
fi 