forge verify-contract \
  --rpc-url https://rpc-gel-sepolia.inkonchain.com \
  --verifier blockscout \
  --verifier-url 'https://explorer-sepolia.inkonchain.com/api/' \
  $HOOK_ADDRESS \
  src/kvhook.sol:kvhook

forge verify-contract \
  --rpc-url https://rpc-gel-sepolia.inkonchain.com \
  --verifier blockscout \
  --verifier-url 'https://explorer-sepolia.inkonchain.com/api/' \
  $POOL_MANAGER_ADDRESS \
  lib/uniswap-hooks/lib/v4-core/src/PoolManager.sol:PoolManager