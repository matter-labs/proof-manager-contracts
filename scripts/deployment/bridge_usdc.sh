#!/bin/bash
set -euo pipefail

# === Get chain name (from input or default to "era") ===
CHAIN_NAME="${1:-era}"
export CHAIN_NAME

echo "STARTING BRIDGE TOKEN TO $CHAIN_NAME"

export NTV_ADDRESS=$NTV_ADDRESS
export BH_ADDRESS=$BH_ADDRESS
export SHARED_BRIDGE_L1_ADDRESS=$SHARED_BRIDGE_L1_ADDRESS
export L1_RPC_URL=$L1_RPC_URL # RPC URL of L1
export L2_RPC_URL=$L2_RPC_URL # RPC URL of L2
export L1_CHAIN_ID=$(cast chain-id)
export PRIVATE_KEY=$PRIVATE_KEY
export SENDER=$SENDER
export CHAIN_ID=$L2_CHAIN_ID
export TOKEN_ADDRESS=$TOKEN_ADDRESS
export AMOUNT=$AMOUNT

echo "CHAIN_ID: $CHAIN_ID"
echo "TOKEN_ADDRESS: $TOKEN_ADDRESS"

export TOKEN_ASSET_ID=$(cast keccak $(cast abi-encode "selectorNotUsed(uint256,address,address)" \
  $(printf "0x%02x\n" "$L1_CHAIN_ID") \
  0x0000000000000000000000000000000000010004 \
  "$TOKEN_ADDRESS"))

# === Build bridge calldata ===
ENCODED_PAYLOAD=$(cast abi-encode "selectorNotUsed(uint256,address,address)" \
  100 \
  $SENDER \
  "$TOKEN_ADDRESS" | cut -c 3-)

export BRIDGE_DATA="0x01${TOKEN_ASSET_ID:2}00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000060$ENCODED_PAYLOAD"

echo "TOKEN_ASSET_ID: $TOKEN_ASSET_ID"

export GAS_PRICE=$(cast gas-price --rpc-url $RPC_URL)

# We assume that sender already has the amount of tokens to bridge

cast send --from $SENDER \
  --private-key $PRIVATE_KEY \
  "$TOKEN_ADDRESS" \
  "approve(address,uint256)" "$NTV_ADDRESS" $AMOUNT \
  --rpc-url $RPC_URL \
  --gas-price $GAS_PRICE

# === Send message through bridge ===
cast send --from $SENDER \
  --private-key $PRIVATE_KEY \
  "$BH_ADDRESS" \
  "requestL2TransactionTwoBridges((uint256,uint256,uint256,uint256,uint256,address,address,uint256,bytes))" \
  "(271,10000000000000000000000000000000,0,10000000,800,$SENDER,$SHARED_BRIDGE_L1_ADDRESS,0,$BRIDGE_DATA)" \
  --gas-limit 10000000 \
  --value 10000000000000000000000000000000 \
  --rpc-url $RPC_URL \
  --gas-price 100000

L2_TOKEN_ADDRESS=$(cast call 0x0000000000000000000000000000000000010004  "tokenAddress(bytes32)(address)" $TOKEN_ASSET_ID  --rpc-url $L2_RPC_URL)

echo "Token address on L2: $L2_TOKEN_ADDRESS"