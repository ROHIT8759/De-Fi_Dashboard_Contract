// ELEGENT DeFi Platform - Move Smart Contracts for Aptos
// File: sources/elegent.move

module elegent::elegent_defi {
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::timestamp;
    use std::error;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::table::{Self, Table};

    // Error codes
    const E_NOT_INITIALIZED: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_INSUFFICIENT_TRUST_SCORE: u64 = 3;
    const E_LOAN_NOT_FOUND: u64 = 4;
    const E_INSUFFICIENT_FUNDS: u64 = 5;
    const E_LOAN_ALREADY_REPAID: u64 = 6;
    const E_UNAUTHORIZED: u64 = 7;
    const E_INVALID_AMOUNT: u64 = 8;
    const E_LOAN_OVERDUE: u64 = 9;

    // Constants
    const INITIAL_TRUST_SCORE: u64 = 100;
    const MAX_TRUST_SCORE: u64 = 1000;
    const MIN_LOAN_AMOUNT: u64 = 1000000; // 0.01 APT (8 decimals)
    const MAX_LOAN_AMOUNT: u64 = 100000000000; // 1000 APT
    const LOAN_DURATION_SECONDS: u64 = 2592000; // 30 days
    const INTEREST_RATE_BPS: u64 = 500; // 5% APR
    const STAKING_REWARD_BPS: u64 = 1000; // 10% APY

    // TrustScore NFT structure
    struct TrustScoreNFT has key {
        score: u64,
        tier: String,
        loan_count: u64,
        total_borrowed: u64,
        total_repaid: u64,
        defaults: u64,
        last_updated: u64,
        staked_amount: u64,
        wallet_age: u64,
    }

    // Loan structure
    struct Loan has store, copy, drop {
        id: u64,
        borrower: address,
        amount: u64,
        interest_amount: u64,
        due_date: u64,
        status: u8, // 0: active, 1: repaid, 2: defaulted
        created_at: u64,
    }

    // Platform state
    struct PlatformState has key {
        total_loans: u64,
        total_volume: u64,
        active_loans: Table<u64, Loan>,
        user_loans: Table<address, vector<u64>>,
        treasury_balance: u64,
        is_paused: bool,
        admin: address,
    }

    // Staking pool
    struct StakingPool has key {
        total_staked: u64,
        user_stakes: Table<address, u64>,
        user_rewards: Table<address, u64>,
        pending_withdrawals: Table<address, u64>,
        last_reward_time: u64,
    }

    // Events
    struct LoanCreatedEvent has drop, store {
        loan_id: u64,
        borrower: address,
        amount: u64,
        due_date: u64,
    }

    struct LoanRepaidEvent has drop, store {
        loan_id: u64,
        borrower: address,
        amount: u64,
        interest: u64,
    }

    struct TrustScoreUpdatedEvent has drop, store {
        user: address,
        old_score: u64,
        new_score: u64,
        tier: String,
    }

    struct StakeEvent has drop, store {
        user: address,
        amount: u64,
        total_staked: u64,
    }

    // Event handles
    struct EventHandles has key {
        loan_created_events: event::EventHandle<LoanCreatedEvent>,
        loan_repaid_events: event::EventHandle<LoanRepaidEvent>,
        trust_score_updated_events: event::EventHandle<TrustScoreUpdatedEvent>,
        stake_events: event::EventHandle<StakeEvent>,
    }

    // Initialize the platform
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(!exists<PlatformState>(admin_addr), error::already_exists(E_ALREADY_INITIALIZED));

        move_to(admin, PlatformState {
            total_loans: 0,
            total_volume: 0,
            active_loans: table::new(),
            user_loans: table::new(),
            treasury_balance: 0,
            is_paused: false,
            admin: admin_addr,
        });

        move_to(admin, StakingPool {
            total_staked: 0,
            user_stakes: table::new(),
            user_rewards: table::new(),
            pending_withdrawals: table::new(),
            last_reward_time: timestamp::now_seconds(),
        });

        move_to(admin, EventHandles {
            loan_created_events: account::new_event_handle<LoanCreatedEvent>(admin),
            loan_repaid_events: account::new_event_handle<LoanRepaidEvent>(admin),
            trust_score_updated_events: account::new_event_handle<TrustScoreUpdatedEvent>(admin),
            stake_events: account::new_event_handle<StakeEvent>(admin),
        });
    }

    // Create initial TrustScore NFT for new users
    public entry fun create_trust_score(account: &signer) {
        let user_addr = signer::address_of(account);
        assert!(!exists<TrustScoreNFT>(user_addr), error::already_exists(E_ALREADY_INITIALIZED));

        let wallet_age = calculate_wallet_age(user_addr);
        let initial_score = INITIAL_TRUST_SCORE + (wallet_age / 86400 / 30); // Bonus for wallet age

        move_to(account, TrustScoreNFT {
            score: initial_score,
            tier: get_tier_from_score(initial_score),
            loan_count: 0,
            total_borrowed: 0,
            total_repaid: 0,
            defaults: 0,
            last_updated: timestamp::now_seconds(),
            staked_amount: 0,
            wallet_age,
        });
    }

    // Request a loan
    public entry fun request_loan(
        borrower: &signer,
        amount: u64,
        platform_admin: address
    ) acquires PlatformState, TrustScoreNFT, EventHandles {
        let borrower_addr = signer::address_of(borrower);
        
        assert!(exists<TrustScoreNFT>(borrower_addr), error::not_found(E_NOT_INITIALIZED));
        assert!(amount >= MIN_LOAN_AMOUNT && amount <= MAX_LOAN_AMOUNT, error::invalid_argument(E_INVALID_AMOUNT));

        let trust_score = borrow_global<TrustScoreNFT>(borrower_addr);
        let max_loan_amount = calculate_max_loan_amount(trust_score.score, trust_score.staked_amount);
        assert!(amount <= max_loan_amount, error::permission_denied(E_INSUFFICIENT_TRUST_SCORE));

        let platform_state = borrow_global_mut<PlatformState>(platform_admin);
        assert!(!platform_state.is_paused, error::unavailable(E_UNAUTHORIZED));

        let loan_id = platform_state.total_loans + 1;
        let interest_amount = (amount * INTEREST_RATE_BPS) / 10000;
        let due_date = timestamp::now_seconds() + LOAN_DURATION_SECONDS;

        let loan = Loan {
            id: loan_id,
            borrower: borrower_addr,
            amount,
            interest_amount,
            due_date,
            status: 0, // active
            created_at: timestamp::now_seconds(),
        };

        table::add(&mut platform_state.active_loans, loan_id, loan);
        
        if (!table::contains(&platform_state.user_loans, borrower_addr)) {
            table::add(&mut platform_state.user_loans, borrower_addr, vector::empty<u64>());
        };
        let user_loans = table::borrow_mut(&mut platform_state.user_loans, borrower_addr);
        vector::push_back(user_loans, loan_id);

        platform_state.total_loans = loan_id;
        platform_state.total_volume = platform_state.total_volume + amount;

        // Note: For MVP, loan funds transfer would be handled off-chain
        // In production, this would require a resource account or treasury setup

        // Update trust score
        let trust_score_mut = borrow_global_mut<TrustScoreNFT>(borrower_addr);
        trust_score_mut.loan_count = trust_score_mut.loan_count + 1;
        trust_score_mut.total_borrowed = trust_score_mut.total_borrowed + amount;

        // Emit event
        let event_handles = borrow_global_mut<EventHandles>(platform_admin);
        event::emit_event(&mut event_handles.loan_created_events, LoanCreatedEvent {
            loan_id,
            borrower: borrower_addr,
            amount,
            due_date,
        });
    }

    // Repay a loan
    public entry fun repay_loan(
        borrower: &signer,
        loan_id: u64,
        platform_admin: address
    ) acquires PlatformState, TrustScoreNFT, EventHandles {
        let borrower_addr = signer::address_of(borrower);
        
        let platform_state = borrow_global_mut<PlatformState>(platform_admin);
        assert!(table::contains(&platform_state.active_loans, loan_id), error::not_found(E_LOAN_NOT_FOUND));

        let loan = table::borrow_mut(&mut platform_state.active_loans, loan_id);
        assert!(loan.borrower == borrower_addr, error::permission_denied(E_UNAUTHORIZED));
        assert!(loan.status == 0, error::invalid_state(E_LOAN_ALREADY_REPAID));

        let total_repayment = loan.amount + loan.interest_amount;
        let current_time = timestamp::now_seconds();
        let is_on_time = current_time <= loan.due_date;

        // Transfer repayment
        coin::transfer<AptosCoin>(borrower, platform_admin, total_repayment);

        // Update loan status
        loan.status = 1; // repaid

        // Update trust score
        let trust_score = borrow_global_mut<TrustScoreNFT>(borrower_addr);
        trust_score.total_repaid = trust_score.total_repaid + total_repayment;
        
        let old_score = trust_score.score;
        let score_change = if (is_on_time) { 10 } else { 0 };
        trust_score.score = if (trust_score.score + score_change <= MAX_TRUST_SCORE) {
            trust_score.score + score_change
        } else {
            MAX_TRUST_SCORE
        };
        trust_score.tier = get_tier_from_score(trust_score.score);
        trust_score.last_updated = current_time;

        // Emit events
        let event_handles = borrow_global_mut<EventHandles>(platform_admin);
        event::emit_event(&mut event_handles.loan_repaid_events, LoanRepaidEvent {
            loan_id,
            borrower: borrower_addr,
            amount: loan.amount,
            interest: loan.interest_amount,
        });

        event::emit_event(&mut event_handles.trust_score_updated_events, TrustScoreUpdatedEvent {
            user: borrower_addr,
            old_score,
            new_score: trust_score.score,
            tier: trust_score.tier,
        });
    }

    // Stake APT to increase loan limits
    public entry fun stake_apt(
        user: &signer,
        amount: u64,
        platform_admin: address
    ) acquires StakingPool, TrustScoreNFT, EventHandles {
        let user_addr = signer::address_of(user);
        assert!(exists<TrustScoreNFT>(user_addr), error::not_found(E_NOT_INITIALIZED));
        assert!(amount > 0, error::invalid_argument(E_INVALID_AMOUNT));

        // Transfer APT to staking pool
        coin::transfer<AptosCoin>(user, platform_admin, amount);

        let staking_pool = borrow_global_mut<StakingPool>(platform_admin);
        
        if (!table::contains(&staking_pool.user_stakes, user_addr)) {
            table::add(&mut staking_pool.user_stakes, user_addr, 0);
            table::add(&mut staking_pool.user_rewards, user_addr, 0);
            table::add(&mut staking_pool.pending_withdrawals, user_addr, 0);
        };

        let user_stake = table::borrow_mut(&mut staking_pool.user_stakes, user_addr);
        *user_stake = *user_stake + amount;
        staking_pool.total_staked = staking_pool.total_staked + amount;

        // Update trust score
        let trust_score = borrow_global_mut<TrustScoreNFT>(user_addr);
        trust_score.staked_amount = trust_score.staked_amount + amount;
        trust_score.score = trust_score.score + (amount / 1000000); // 1 point per 0.01 APT staked

        // Emit event
        let event_handles = borrow_global_mut<EventHandles>(platform_admin);
        event::emit_event(&mut event_handles.stake_events, StakeEvent {
            user: user_addr,
            amount,
            total_staked: *user_stake,
        });
    }

    // Unstake APT (request withdrawal)
    public entry fun unstake_apt(
        user: &signer,
        amount: u64,
        platform_admin: address
    ) acquires StakingPool, TrustScoreNFT {
        let user_addr = signer::address_of(user);
        
        let staking_pool = borrow_global_mut<StakingPool>(platform_admin);
        assert!(table::contains(&staking_pool.user_stakes, user_addr), error::not_found(E_NOT_INITIALIZED));

        let user_stake = table::borrow_mut(&mut staking_pool.user_stakes, user_addr);
        assert!(*user_stake >= amount, error::invalid_argument(E_INSUFFICIENT_FUNDS));

        *user_stake = *user_stake - amount;
        staking_pool.total_staked = staking_pool.total_staked - amount;

        // Add to pending withdrawals (admin needs to process these manually)
        let pending_withdrawal = table::borrow_mut(&mut staking_pool.pending_withdrawals, user_addr);
        *pending_withdrawal = *pending_withdrawal + amount;

        // Update trust score
        let trust_score = borrow_global_mut<TrustScoreNFT>(user_addr);
        trust_score.staked_amount = trust_score.staked_amount - amount;
    }

    // View functions
    #[view]
    public fun get_trust_score(user: address): (u64, String) acquires TrustScoreNFT {
        assert!(exists<TrustScoreNFT>(user), error::not_found(E_NOT_INITIALIZED));
        let trust_score = borrow_global<TrustScoreNFT>(user);
        (trust_score.score, trust_score.tier)
    }

    #[view]
    public fun get_max_loan_amount(user: address): u64 acquires TrustScoreNFT {
        assert!(exists<TrustScoreNFT>(user), error::not_found(E_NOT_INITIALIZED));
        let trust_score = borrow_global<TrustScoreNFT>(user);
        calculate_max_loan_amount(trust_score.score, trust_score.staked_amount)
    }

    #[view]
    public fun get_user_loans(user: address, platform_admin: address): vector<u64> acquires PlatformState {
        let platform_state = borrow_global<PlatformState>(platform_admin);
        if (table::contains(&platform_state.user_loans, user)) {
            *table::borrow(&platform_state.user_loans, user)
        } else {
            vector::empty<u64>()
        }
    }

    #[view]
    public fun get_loan_details(loan_id: u64, platform_admin: address): (u64, address, u64, u64, u64, u8) acquires PlatformState {
        let platform_state = borrow_global<PlatformState>(platform_admin);
        assert!(table::contains(&platform_state.active_loans, loan_id), error::not_found(E_LOAN_NOT_FOUND));
        
        let loan = table::borrow(&platform_state.active_loans, loan_id);
        (loan.id, loan.borrower, loan.amount, loan.interest_amount, loan.due_date, loan.status)
    }

    #[view]
    public fun get_pending_withdrawal(user: address, platform_admin: address): u64 acquires StakingPool {
        let staking_pool = borrow_global<StakingPool>(platform_admin);
        if (table::contains(&staking_pool.pending_withdrawals, user)) {
            *table::borrow(&staking_pool.pending_withdrawals, user)
        } else {
            0
        }
    }

    // Helper functions
    fun calculate_max_loan_amount(trust_score: u64, staked_amount: u64): u64 {
        let base_amount = (trust_score * 1000000) / 100; // 0.01 APT per trust score point
        let staking_bonus = staked_amount * 2; // 2x leverage on staked amount
        base_amount + staking_bonus
    }

    fun get_tier_from_score(score: u64): String {
        if (score >= 800) {
            string::utf8(b"Platinum")
        } else if (score >= 600) {
            string::utf8(b"Gold")
        } else if (score >= 400) {
            string::utf8(b"Silver")
        } else {
            string::utf8(b"Bronze")
        }
    }

    fun calculate_wallet_age(_user: address): u64 {
        // This is a simplified calculation
        // In practice, you'd query the blockchain for first transaction
        timestamp::now_seconds() - 1000000 // Placeholder
    }

    // Admin functions
    public entry fun pause_platform(admin: &signer, platform_admin: address) acquires PlatformState {
        let admin_addr = signer::address_of(admin);
        let platform_state = borrow_global_mut<PlatformState>(platform_admin);
        assert!(admin_addr == platform_state.admin, error::permission_denied(E_UNAUTHORIZED));
        platform_state.is_paused = true;
    }

    public entry fun unpause_platform(admin: &signer, platform_admin: address) acquires PlatformState {
        let admin_addr = signer::address_of(admin);
        let platform_state = borrow_global_mut<PlatformState>(platform_admin);
        assert!(admin_addr == platform_state.admin, error::permission_denied(E_UNAUTHORIZED));
        platform_state.is_paused = false;
    }
}