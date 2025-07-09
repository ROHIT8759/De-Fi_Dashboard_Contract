#!/bin/bash
# simple_deploy.sh - Simplified deployment script

set -e  # Exit on any error

echo "🚀 ELEGENT DeFi Simple Deployment"
echo "================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NETWORK=${1:-testnet}
PROFILE=${NETWORK}

echo -e "${YELLOW}Network: $NETWORK${NC}"
echo -e "${YELLOW}Profile: $PROFILE${NC}"
echo ""

# Step 1: Compile
echo "🔨 Step 1: Compiling..."
aptos move compile
echo -e "${GREEN}✅ Compilation successful${NC}"
echo ""

# Step 2: Get profile address
echo "📍 Step 2: Getting profile address..."
PROFILE_ADDR=$(aptos config show-profiles --profile $PROFILE | grep "account" | cut -d' ' -f2)
echo -e "${GREEN}Profile Address: $PROFILE_ADDR${NC}"
echo ""

# Step 3: Check account funding
echo "💰 Step 3: Checking account funding..."
if aptos account show --profile $PROFILE >/dev/null 2>&1; then
    BALANCE=$(aptos account show --profile $PROFILE | grep "coin" -A 5 | grep "value" | cut -d'"' -f4)
    echo -e "${GREEN}✅ Account funded with $BALANCE octas${NC}"
else
    echo -e "${RED}❌ Account not funded. Please visit:${NC}"
    echo -e "${YELLOW}https://aptos.dev/network/faucet?address=$PROFILE_ADDR${NC}"
    echo ""
    echo "After funding, run this script again."
    exit 1
fi
echo ""

# Step 4: Deploy
echo "🚀 Step 4: Deploying..."
aptos move publish --profile $PROFILE --assume-yes --named-addresses elegent=$PROFILE_ADDR
echo -e "${GREEN}✅ Deployment successful${NC}"
echo ""

# Step 5: Initialize
echo "🏗️ Step 5: Initializing platform..."
if aptos move run --function-id ${PROFILE_ADDR}::elegent_defi::initialize --profile $PROFILE; then
    echo -e "${GREEN}✅ Platform initialized${NC}"
else
    echo -e "${YELLOW}⚠️ Initialization failed (might already be initialized)${NC}"
fi
echo ""

# Success
echo -e "${GREEN}🎉 Deployment completed!${NC}"
echo ""
echo "Contract Address: $PROFILE_ADDR"
echo "Network: $NETWORK"
echo ""
echo "Next steps:"
echo "1. Create trust score: aptos move run --function-id ${PROFILE_ADDR}::elegent_defi::create_trust_score --profile $PROFILE"
echo "2. Check functions in DEPLOYMENT_INSTRUCTIONS.md"
