;; SubNFTx: Tokenized Subscription Framework
;; A contract for managing subscription-based access via NFTs

;; Define NFT trait
(define-trait nft-trait
    (
        ;; Last token ID
        (get-last-token-id () (response uint uint))
        ;; URI for token metadata
        (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
        ;; Owner of a token
        (get-owner (uint) (response (optional principal) uint))
        ;; Transfer token
        (transfer (uint principal principal) (response bool uint))
    )
)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_INVALID_SUBSCRIPTION (err u102))
(define-constant ERR_EXPIRED (err u103))
(define-constant ERR_NFT_NOT_FOUND (err u104))
(define-constant ERR_CONTENT_NOT_FOUND (err u105))

;; Data Variables
(define-data-var contract-enabled bool true)
(define-data-var last-token-id uint u0)

;; Define subscription tiers
(define-map subscription-tiers
    uint  ;; tier-id
    {
        name: (string-ascii 24),
        duration: uint,         ;; duration in blocks
        price: uint            ;; price in STX
    }
)

;; Track active subscriptions and associated NFTs
(define-map active-subscriptions
    principal  ;; subscriber address
    {
        tier-id: uint,
        expires-at: uint,      ;; block height when subscription expires
        active: bool,
        token-id: uint        ;; associated NFT token ID
    }
)

;; NFT ownership tracking
(define-map token-owners 
    uint  ;; token-id 
    principal
)

;; Content access rights per tier
(define-map content-access-rights
    {content-id: uint, tier-id: uint}
    bool
)

;; Content metadata
(define-map content-metadata
    uint  ;; content-id
    {
        name: (string-ascii 64),
        creator: principal,
        min-tier: uint
    }
)

;; NFT Implementation

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-owner? sender token-id) ERR_NOT_AUTHORIZED)
        (map-set token-owners token-id recipient)
        (ok true)
    )
)

(define-public (get-token-uri (token-id uint))
    (ok none)
)

(define-read-only (get-owner (token-id uint))
    (ok (map-get? token-owners token-id))
)

(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
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

(define-read-only (can-access-content (user principal) (content-id uint))
    (let (
        (subscription (unwrap! (map-get? active-subscriptions user) false))
        (content (unwrap! (map-get? content-metadata content-id) false))
    )
    (and
        (is-subscription-active user)
        (>= (get tier-id subscription) (get min-tier content))
        (is-owner? user (get token-id subscription))
    ))
)

(define-private (is-owner? (user principal) (token-id uint))
    (match (map-get? token-owners token-id)
        owner (is-eq owner user)
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

;; Mint NFT for new subscription
(define-private (mint-subscription-nft (recipient principal))
    (let (
        (token-id (+ (var-get last-token-id) u1))
    )
    (begin
        (var-set last-token-id token-id)
        (map-set token-owners token-id recipient)
        token-id
    ))
)

;; Subscribe to a tier
(define-public (subscribe (tier-id uint))
    (let (
        (tier (unwrap! (map-get? subscription-tiers tier-id) ERR_INVALID_SUBSCRIPTION))
        (current-subscription (map-get? active-subscriptions tx-sender))
        (new-token-id (mint-subscription-nft tx-sender))
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
                active: true,
                token-id: new-token-id
            }))
        )
    ))
)

;; Cancel subscription
(define-public (cancel-subscription)
    (let (
        (subscription (unwrap! (map-get? active-subscriptions tx-sender) ERR_INVALID_SUBSCRIPTION))
    )
    (begin
        (map-delete token-owners (get token-id subscription))
        (ok (map-set active-subscriptions tx-sender {
            tier-id: u0,
            expires-at: u0,
            active: false,
            token-id: u0
        }))
    ))
)

;; Content Management

(define-public (add-content (content-id uint) (name (string-ascii 64)) (min-tier uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_NOT_AUTHORIZED)
        (ok (map-set content-metadata content-id {
            name: name,
            creator: tx-sender,
            min-tier: min-tier
        }))
    )
)

(define-public (set-content-access (content-id uint) (tier-id uint) (has-access bool))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_NOT_AUTHORIZED)
        (ok (map-set content-access-rights {content-id: content-id, tier-id: tier-id} has-access))
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