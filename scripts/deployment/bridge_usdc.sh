#!/bin/bash
set -euo pipefail

# === Get chain name (from input or default to "era") ===
CHAIN_NAME="${1:-era}"
export CHAIN_NAME

echo "STARTING BRIDGE TOKEN TO $CHAIN_NAME"

export BH_ADDRESS=$BH_ADDRESS
export SHARED_BRIDGE_L1_ADDRESS=$SHARED_BRIDGE_L1_ADDRESS
export L1_RPC_URL=$L1_RPC_URL # RPC URL of L1
export L2_RPC_URL=$L2_RPC_URL # RPC URL of L2
export L1_CHAIN_ID=$(cast chain-id --rpc-url $L1_RPC_URL)
export L2_CHAIN_ID=$(cast chain-id --rpc-url $L2_RPC_URL)
export PRIVATE_KEY=$PRIVATE_KEY
export SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
export TOKEN_ADDRESS=$TOKEN_ADDRESS
export AMOUNT=$AMOUNT

echo "Bridging $AMOUNT $TOKEN_ADDRESS from $L1_CHAIN_ID to $L2_CHAIN_ID with sender $SENDER"

export TOKEN_ASSET_ID=$(cast keccak $(cast abi-encode "selectorNotUsed(uint256,address,address)" \
  $(printf "0x%02x\n" "$L1_CHAIN_ID") \
  0x0000000000000000000000000000000000010004 \
  "$TOKEN_ADDRESS"))

# === Build bridge calldata ===
TRANSFER_DATA=$(cast abi-encode "selectorNotUsed(uint256,address,address)" \
  $AMOUNT \
  $SENDER \
  $TOKEN_ADDRESS)

CALLDATA_PAYLOAD=$(cast abi-encode "selectorNotUsed(bytes32,bytes)" \
  $TOKEN_ASSET_ID \
  $TRANSFER_DATA)

export BRIDGE_DATA="0x01${CALLDATA_PAYLOAD:2}"

echo "BRIDGE_DATA: $BRIDGE_DATA"

echo "TOKEN_ASSET_ID: $TOKEN_ASSET_ID"

CURRENT_BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" $SENDER --rpc-url $L1_RPC_URL | awk '{print $1}')

CURRENT_ALLOWANCE=$(cast call $TOKEN_ADDRESS "allowance(address,address)(uint256)" $SENDER $NTV_ADDRESS --rpc-url $L1_RPC_URL | awk '{print $1}')
export GAS_PRICE=$(cast gas-price --rpc-url $L1_RPC_URL)

echo "GAS_PRICE: $GAS_PRICE"

if [ $CURRENT_ALLOWANCE -lt $AMOUNT ]; then
  cast send --from $SENDER \
    --private-key $PRIVATE_KEY \
    "$TOKEN_ADDRESS" \
    "approve(address,uint256)" "$NTV_ADDRESS" $AMOUNT \
    --rpc-url $L1_RPC_URL \
    --gas-price $GAS_PRICE
fi

CURRENT_ALLOWANCE=$(cast call $TOKEN_ADDRESS "allowance(address,address)(uint256)" $SENDER $NTV_ADDRESS --rpc-url $L1_RPC_URL | awk '{print $1}')

 # 1) compute base cost with the EXACT gas price you’ll send with
GAS_PRICE=$(cast gas-price --rpc-url $L1_RPC_URL)
L2_GAS_LIMIT=10000000
PUBDATA=800
MINT_VALUE=$(cast call $BH_ADDRESS \
  'l2TransactionBaseCost(uint256,uint256,uint256,uint256)(uint256)' \
  $L2_CHAIN_ID $GAS_PRICE $L2_GAS_LIMIT $PUBDATA \
  --rpc-url $L1_RPC_URL | awk '{print $1}')

# 2) send paying that amount (and pin the same gas price)
cast send --from $SENDER --private-key $PRIVATE_KEY "$BH_ADDRESS" \
  'requestL2TransactionTwoBridges((uint256,uint256,uint256,uint256,uint256,address,address,uint256,bytes))' \
  "($L2_CHAIN_ID,$MINT_VALUE,0,$L2_GAS_LIMIT,$PUBDATA,$SENDER,$SHARED_BRIDGE_L1_ADDRESS,0,$BRIDGE_DATA)" \
  --rpc-url $L1_RPC_URL \
  --gas-limit $L2_GAS_LIMIT \
  --gas-price $GAS_PRICE \
  --legacy \
  --value $MINT_VALUE


L2_TOKEN_ADDRESS=$(cast call 0x0000000000000000000000000000000000010004  "tokenAddress(bytes32)(address)" $TOKEN_ASSET_ID  --rpc-url $L2_RPC_URL)

echo "Token address on L2: $L2_TOKEN_ADDRESS. If this value is 0, the token is not bridged yet, you can try to run the following query to check again later:

cast call 0x0000000000000000000000000000000000010004  \"tokenAddress(bytes32)(address)\" $TOKEN_ASSET_ID  --rpc-url $L2_RPC_URL"
