;; SubNFTx: Tokenized Subscription Framework
;; A contract for managing subscription-based access via NFTs

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_INVALID_SUBSCRIPTION (err u102))
(define-constant ERR_EXPIRED (err u103))

;; Data Variables
(define-data-var contract-enabled bool true)

;; Define subscription tiers
(define-map subscription-tiers
    uint  ;; tier-id
    {
        name: (string-ascii 24),
        duration: uint,         ;; duration in blocks
        price: uint            ;; price in STX
    }
)

;; Track active subscriptions
(define-map active-subscriptions
    principal  ;; subscriber address
    {
        tier-id: uint,
        expires-at: uint,      ;; block height when subscription expires
        active: bool
    }
)

;; Read-only functions

(define-read-only (get-subscription-tier (tier-id uint))
    (map-get? subscription-tiers tier-id)
)

(define-read-only (get-active-subscription (subscriber principal))
    (map-get? active-subscriptions subscriber)
)

(define-read-only (is-subscription-active (subscriber principal))
    (match (map-get? active-subscriptions subscriber)
        subscription (and 
            (get active subscription)
            (< block-height (get expires-at subscription))
        )
        false
    )
)

;; Public functions

;; Create a new subscription tier (admin only)
(define-public (create-subscription-tier (tier-id uint) (name (string-ascii 24)) (duration uint) (price uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (map-get? subscription-tiers tier-id)) ERR_ALREADY_EXISTS)
        (ok (map-set subscription-tiers tier-id {
            name: name,
            duration: duration,
            price: price
        }))
    )
)

;; Subscribe to a tier
(define-public (subscribe (tier-id uint))
    (let (
        (tier (unwrap! (map-get? subscription-tiers tier-id) ERR_INVALID_SUBSCRIPTION))
        (current-subscription (map-get? active-subscriptions tx-sender))
    )
    (begin
        (asserts! (is-contract-enabled) ERR_NOT_AUTHORIZED)
        ;; Transfer payment
        (try! (stx-transfer? (get price tier) tx-sender CONTRACT_OWNER))
        
        ;; Calculate expiration
        (let ((new-expiration (+ block-height (get duration tier))))
            (ok (map-set active-subscriptions tx-sender {
                tier-id: tier-id,
                expires-at: new-expiration,
                active: true
            }))
        )
    ))
)

;; Cancel subscription
(define-public (cancel-subscription)
    (begin
        (asserts! (is-some (map-get? active-subscriptions tx-sender)) ERR_INVALID_SUBSCRIPTION)
        (ok (map-set active-subscriptions tx-sender {
            tier-id: u0,
            expires-at: u0,
            active: false
        }))
    )
)

;; Administrative functions

(define-private (is-contract-owner (caller principal))
    (is-eq caller CONTRACT_OWNER)
)

(define-public (toggle-contract (enabled bool))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_NOT_AUTHORIZED)
        (ok (var-set contract-enabled enabled))
    )
)

(define-private (is-contract-enabled)
    (var-get contract-enabled)
)

;; Initialize contract
(begin
    ;; Initialize Bronze Tier
    (try! (create-subscription-tier u1 "Bronze" u144 u100000000))  ;; 100 STX, 1 day
    ;; Initialize Silver Tier
    (try! (create-subscription-tier u2 "Silver" u4320 u250000000)) ;; 250 STX, 30 days
    ;; Initialize Gold Tier
    (try! (create-subscription-tier u3 "Gold" u52560 u1000000000)) ;; 1000 STX, 365 days
    
    (print "SubNFTx contract initialized")
)