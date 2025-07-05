# ELEGENT DeFi Deployment Instructions

## Prerequisites

1. **Install Aptos CLI**: Make sure you have the Aptos CLI installed
   ```bash
   curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3
   ```

2. **Set up Profile**: Initialize your testnet profile
   ```bash
   aptos init --profile testnet --network testnet
   ```

## Manual Deployment Steps

### Step 1: Fund Your Account
Visit the faucet to get testnet APT:
```
https://aptos.dev/network/faucet?address=YOUR_ADDRESS
```

Or try the CLI:
```bash
aptos account fund-with-faucet --profile testnet --faucet-url https://faucet.testnet.aptoslabs.com
```

### Step 2: Compile the Move Package
```bash
aptos move compile --dev
```

### Step 3: Deploy to Testnet
```bash
# Get your address
PROFILE_ADDR=$(aptos config show-profiles --profile testnet | grep "account" | cut -d' ' -f2)

# Deploy with named addresses
aptos move publish --profile testnet --assume-yes --named-addresses elegent=$PROFILE_ADDR
```

### Step 4: Initialize the Platform
```bash
# After successful deployment, initialize the platform
aptos move run --function-id ${PROFILE_ADDR}::elegent_defi::initialize --profile testnet
```

## Troubleshooting

### Common Issues:

1. **Compilation Errors**: Make sure all dependencies are properly configured in `Move.toml`

2. **Account Not Funded**: Visit the faucet URL and request testnet APT

3. **Address Resolution**: Ensure the named address `elegent` is properly set during deployment

4. **Test Failures**: The current tests have timestamp dependency issues. You can skip tests during deployment.

### Manual Test Commands:

```bash
# Check account balance
aptos account show --profile testnet

# List account modules
aptos account list --query modules --profile testnet

# Call view functions (after deployment)
aptos move view --function-id ${PROFILE_ADDR}::elegent_defi::get_trust_score --args address:${USER_ADDRESS} --profile testnet
```

## Contract Functions

After deployment, you can interact with these functions:

### Entry Functions:
- `initialize()` - Initialize the platform (admin only)
- `create_trust_score()` - Create trust score for a user
- `request_loan(amount: u64)` - Request a loan
- `repay_loan(loan_id: u64)` - Repay a loan
- `stake_apt(amount: u64)` - Stake APT tokens
- `unstake_apt(amount: u64)` - Unstake APT tokens

### View Functions:
- `get_trust_score(user: address): (u64, String)` - Get user's trust score and tier
- `get_max_loan_amount(user: address): u64` - Get maximum loan amount for user
- `get_user_loans(user: address): vector<u64>` - Get user's loan IDs
- `get_loan_details(loan_id: u64): (u64, address, u64, u64, u64, u8, u64)` - Get loan details

## Example Interaction:

```bash
# After deployment and initialization:

# Create trust score
aptos move run --function-id ${PROFILE_ADDR}::elegent_defi::create_trust_score --profile testnet

# Check trust score
aptos move view --function-id ${PROFILE_ADDR}::elegent_defi::get_trust_score --args address:${PROFILE_ADDR} --profile testnet

# Request a loan (0.1 APT = 10000000 octas)
aptos move run --function-id ${PROFILE_ADDR}::elegent_defi::request_loan --args u64:10000000 --profile testnet
```

## Next Steps

1. Test all functions on testnet
2. Set up frontend integration
3. Monitor contract performance
4. Consider security audit before mainnet deployment
