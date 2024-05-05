module data_marketplace::data_marketplace {

    // Imports
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Option, none, some, is_some, contains, borrow};
    use std::vector;
    use sui::object::{ImmutableObject, ID};

        struct CategoryRatingInfo has copy, drop {
        total_rating: u64,
        listing_count: u64,
    }

    // Errors
    const EInvalidBid: u64 = 1;
    const EInvalidData: u64 = 2;
    const EDispute: u64 = 3;
    const EAlreadyResolved: u64 = 4;
    const ENotProvider: u64 = 5;
    const EInvalidWithdrawal: u64 = 7;

    // Struct definitions
    struct DataListing has key, store {
        id: UID,
        provider: address,
        consumer: Option<address>,
        description: vector<u8>,
        price: u64,
        escrow: Balance<SUI>,
        dataSubmitted: bool,
        dispute: bool,
        category: vector<u8>,
        tags: vector<u8>,
        rating: u32,
        reviews: vector<vector<u8>>,
    }

    // Accessors
    public entry fun get_listing_description(listing: &DataListing): vector<u8> {
        listing.description
    }

    public entry fun get_listing_price(listing: &DataListing): u64 {
        listing.price
    }

    public entry fun get_listing_category(listing: &DataListing): vector<u8> {
        listing.category
    }

    public entry fun get_listing_tags(listing: &DataListing): vector<u8> {
        listing.tags
    }

    public entry fun get_listing_rating(listing: &DataListing): u32 {
        listing.rating
    }

    public entry fun get_listing_reviews(listing: &DataListing): vector<vector<u8>> {
        listing.reviews
    }

    // Public - Entry functions
    public entry fun create_listing(description: vector<u8>, price: u64, category: vector<u8>, tags: vector<u8>, ctx: &mut TxContext) {
        let listing_id = object::new(ctx);
        transfer::share_object(DataListing {
            id: listing_id,
            provider: tx_context::sender(ctx),
            consumer: none(),
            description: description,
            price: price,
            escrow: balance::zero(),
            dataSubmitted: false,
            dispute: false,
            category: category,
            tags: tags,
            rating: 0,
            reviews: vector::empty(),
        });
    }

    public entry fun bid_on_listing(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(!is_some(&listing.consumer), EInvalidBid);
        listing.consumer = some(tx_context::sender(ctx));
    }

    public entry fun submit_data(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(contains(&listing.consumer, &tx_context::sender(ctx)), EInvalidData);
        listing.dataSubmitted = true;
    }

    public entry fun dispute_listing(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx), EDispute);
        listing.dispute = true;
    }

    public entry fun resolve_dispute(listing: &mut DataListing, resolved: bool, ctx: &mut TxContext) {
        assert!(is_some(&listing.consumer), EInvalidBid); // Moved this check
        assert!(listing.provider == tx_context::sender(ctx), EDispute);
        assert!(listing.dispute, EAlreadyResolved);
        let escrow_amount = balance::value(&listing.escrow);
        let escrow_coin = coin::take(&mut listing.escrow, escrow_amount, ctx);
        if (resolved) {
            let consumer = *borrow(&listing.consumer);
            transfer::public_transfer(escrow_coin, consumer);
        } else {
            transfer::public_transfer(escrow_coin, listing.provider);
        };

        listing.consumer = none();
        listing.dataSubmitted = false;
        listing.dispute = false;
    }

    public entry fun release_payment(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx), ENotProvider);
        assert!(listing.dataSubmitted && !listing.dispute, EInvalidWithdrawal); // Updated error code
        assert!(is_some(&listing.consumer), EInvalidBid);
        let consumer = *borrow(&listing.consumer);
        let escrow_amount = balance::value(&listing.escrow);
        let escrow_coin = coin::take(&mut listing.escrow, escrow_amount, ctx);
        transfer::public_transfer(escrow_coin, consumer);

        listing.consumer = none();
        listing.dataSubmitted = false;
        listing.dispute = false;
    }

    // Additional functions
    public entry fun cancel_listing(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx) || contains(&listing.consumer, &tx_context::sender(ctx)), ENotProvider);
        
        if (is_some(&listing.consumer) && !listing.dataSubmitted && !listing.dispute) {
            let escrow_amount = balance::value(&listing.escrow);
            let escrow_coin = coin::take(&mut listing.escrow, escrow_amount, ctx);
            transfer::public_transfer(escrow_coin, listing.provider);
        };

        listing.consumer = none();
        listing.dataSubmitted = false;
        listing.dispute = false;
    }

    public entry fun update_listing_description(listing: &mut DataListing, new_description: vector<u8>, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx), ENotProvider);
        listing.description = new_description;
    }

    public entry fun update_listing_price(listing: &mut DataListing, new_price: u64, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx), ENotProvider);
        listing.price = new_price;
    }

    public entry fun update_listing_category_and_tags(listing: &mut DataListing, new_category: vector<u8>, new_tags: vector<u8>, ctx: &mut TxContext) {
        assert!(listing.provider == tx_context::sender(ctx), ENotProvider);
        listing.category = new_category;
        listing.tags = new_tags;
    }

    public entry fun add_funds_to_listing(listing: &mut DataListing, amount: Coin<SUI>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == listing.provider, ENotProvider);
        let added_balance = coin::into_balance(amount);
        balance::join(&mut listing.escrow, added_balance);
    }

    public entry fun request_refund(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == listing.provider, ENotProvider);
        assert!(listing.dataSubmitted == false, EInvalidWithdrawal);
        let escrow_amount = balance::value(&listing.escrow);
        let escrow_coin = coin::take(&mut listing.escrow, escrow_amount, ctx);
        transfer::public_transfer(escrow_coin, listing.provider);

        listing.consumer = none();
        listing.dataSubmitted = false;
        listing.dispute = false;
    }

    public entry fun mark_listing_complete(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(contains(&listing.consumer, &tx_context::sender(ctx)), ENotProvider);
        listing.dataSubmitted = true;
    }

    public entry fun mark_listing_complete(listing: &mut DataListing, ctx: &mut TxContext) {
        assert!(contains(&listing.consumer, &tx_context::sender(ctx)), ENotProvider);
        listing.dataSubmitted = true;
    }

    public entry fun leave_review_and_rating(listing: &mut DataListing, review: vector<u8>, rating: u32, ctx: &mut TxContext) {
        assert!(contains(&listing.consumer, &tx_context::sender(ctx)), ENotProvider);
        assert!(listing.dataSubmitted && !listing.dispute, EInvalidData);

        listing.reviews = vector::append(&mut listing.reviews, review);
        listing.rating = ((listing.rating * vector::length(&listing.reviews) as u32) + rating) / (vector::length(&listing.reviews) as u32 + 1);
    }

    public fun get_average_rating_for_category(category: &vector<u8>): u32 {
        let category_rating_info = object::fold_uid(DataListing {
            total_rating: 0,
            listing_count: 0,
        }, |info, listing| {
            if (vector::eq_ref(&listing.category, category)) {
                CategoryRatingInfo {
                    total_rating: info.total_rating + listing.rating as u64,
                    listing_count: info.listing_count + 1,
                }
            } else {
                info
            }
        });

        if (category_rating_info.listing_count == 0) {
            0
        } else {
            (category_rating_info.total_rating / category_rating_info.listing_count) as u32
        }
    }
}