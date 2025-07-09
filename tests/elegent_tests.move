// tests/elegent_tests.move
#[test_only]
module elegent::elegent_tests {
    use std::signer;
    use elegent::elegent_defi_v2;

    #[test(admin = @elegent)]
    public fun test_initialize_platform(admin: signer) {
        // Initialize the platform
        elegent_defi_v2::initialize(&admin);
        
        // Test passes if no error is thrown
        assert!(true, 1);
    }

    #[test(admin = @elegent, user = @0x123)]
    public fun test_create_trust_score(admin: signer, user: signer) {
        // Initialize platform first
        elegent_defi_v2::initialize(&admin);
        
        // Create trust score for user
        elegent_defi_v2::create_trust_score(&user);
        
        // Verify trust score was created
        let user_addr = signer::address_of(&user);
        let (score, _tier) = elegent_defi::get_trust_score(user_addr);
        assert!(score >= 100, 2);
    }
}
