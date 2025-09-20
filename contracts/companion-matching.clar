;; Companion Matching Contract
;; Safe matching of elderly individuals with companion volunteers

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-ALREADY-MATCHED (err u104))
(define-constant ERR-INSUFFICIENT-RATING (err u105))
(define-constant ERR-BACKGROUND-CHECK-FAILED (err u106))
(define-constant ERR-AGE-REQUIREMENT (err u107))
(define-constant ERR-INVALID-LOCATION (err u108))
(define-constant ERR-MATCHING-CRITERIA-MISMATCH (err u109))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-volunteer-id uint u1)
(define-data-var next-elderly-id uint u1)
(define-data-var next-match-id uint u1)
(define-data-var minimum-rating uint u3)

;; Status constants
(define-constant STATUS-PENDING "pending")
(define-constant STATUS-VERIFIED "verified")
(define-constant STATUS-ACTIVE "active")
(define-constant STATUS-SUSPENDED "suspended")
(define-constant STATUS-MATCHED "matched")
(define-constant STATUS-AVAILABLE "available")

;; Data maps
(define-map volunteers
    uint
    {
        address: principal,
        name: (string-ascii 100),
        age: uint,
        location: (string-ascii 50),
        skills: (string-ascii 200),
        availability: (string-ascii 100),
        background-check: bool,
        rating: uint,
        status: (string-ascii 20),
        registered-at: uint,
        total-matches: uint
    }
)

(define-map elderly-participants
    uint
    {
        address: principal,
        name: (string-ascii 100),
        age: uint,
        location: (string-ascii 50),
        needs: (string-ascii 200),
        preferences: (string-ascii 200),
        emergency-contact: principal,
        status: (string-ascii 20),
        registered-at: uint,
        current-match-id: (optional uint)
    }
)

(define-map matches
    uint
    {
        volunteer-id: uint,
        elderly-id: uint,
        match-score: uint,
        created-at: uint,
        status: (string-ascii 20),
        last-interaction: uint,
        safety-checks: uint,
        notes: (string-ascii 500)
    }
)

(define-map volunteer-addresses uint principal)
(define-map elderly-addresses uint principal)
(define-map user-volunteer-ids principal uint)
(define-map user-elderly-ids principal uint)
(define-map emergency-contacts principal (list 5 principal))

;; Read-only functions
(define-read-only (get-volunteer (volunteer-id uint))
    (map-get? volunteers volunteer-id)
)

(define-read-only (get-elderly-participant (elderly-id uint))
    (map-get? elderly-participants elderly-id)
)

(define-read-only (get-match (match-id uint))
    (map-get? matches match-id)
)

(define-read-only (get-volunteer-by-address (address principal))
    (match (map-get? user-volunteer-ids address)
        volunteer-id (get-volunteer volunteer-id)
        none
    )
)

(define-read-only (get-elderly-by-address (address principal))
    (match (map-get? user-elderly-ids address)
        elderly-id (get-elderly-participant elderly-id)
        none
    )
)

(define-read-only (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-read-only (calculate-match-score (volunteer-id uint) (elderly-id uint))
    (let
        (
            (volunteer (unwrap! (get-volunteer volunteer-id) u0))
            (elderly (unwrap! (get-elderly-participant elderly-id) u0))
            (location-match (if (is-eq (get location volunteer) (get location elderly)) u30 u0))
            (rating-bonus (* (get rating volunteer) u10))
            (availability-bonus u20)
        )
        (+ location-match rating-bonus availability-bonus)
    )
)

;; Public functions
(define-public (register-volunteer 
    (name (string-ascii 100))
    (age uint)
    (location (string-ascii 50))
    (skills (string-ascii 200))
    (availability (string-ascii 100))
)
    (let
        (
            (volunteer-id (var-get next-volunteer-id))
            (current-block-height block-height)
        )
        (asserts! (>= age u18) ERR-AGE-REQUIREMENT)
        (asserts! (is-none (map-get? user-volunteer-ids tx-sender)) ERR-ALREADY-REGISTERED)
        (asserts! (> (len location) u0) ERR-INVALID-LOCATION)
        
        (map-set volunteers volunteer-id
            {
                address: tx-sender,
                name: name,
                age: age,
                location: location,
                skills: skills,
                availability: availability,
                background-check: false,
                rating: u5,
                status: STATUS-PENDING,
                registered-at: current-block-height,
                total-matches: u0
            }
        )
        
        (map-set volunteer-addresses volunteer-id tx-sender)
        (map-set user-volunteer-ids tx-sender volunteer-id)
        (var-set next-volunteer-id (+ volunteer-id u1))
        
        (ok volunteer-id)
    )
)

(define-public (register-elderly
    (name (string-ascii 100))
    (age uint)
    (location (string-ascii 50))
    (needs (string-ascii 200))
    (preferences (string-ascii 200))
    (emergency-contact principal)
)
    (let
        (
            (elderly-id (var-get next-elderly-id))
            (current-block-height block-height)
        )
        (asserts! (>= age u60) ERR-AGE-REQUIREMENT)
        (asserts! (is-none (map-get? user-elderly-ids tx-sender)) ERR-ALREADY-REGISTERED)
        (asserts! (> (len location) u0) ERR-INVALID-LOCATION)
        (asserts! (not (is-eq emergency-contact tx-sender)) ERR-NOT-AUTHORIZED)
        
        (map-set elderly-participants elderly-id
            {
                address: tx-sender,
                name: name,
                age: age,
                location: location,
                needs: needs,
                preferences: preferences,
                emergency-contact: emergency-contact,
                status: STATUS-ACTIVE,
                registered-at: current-block-height,
                current-match-id: none
            }
        )
        
        (map-set elderly-addresses elderly-id tx-sender)
        (map-set user-elderly-ids tx-sender elderly-id)
        (var-set next-elderly-id (+ elderly-id u1))
        
        (ok elderly-id)
    )
)

(define-public (verify-volunteer (volunteer-id uint) (background-check-passed bool))
    (let
        (
            (volunteer (unwrap! (get-volunteer volunteer-id) ERR-NOT-FOUND))
        )
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status volunteer) STATUS-PENDING) ERR-INVALID-STATUS)
        
        (if background-check-passed
            (map-set volunteers volunteer-id
                (merge volunteer {
                    background-check: true,
                    status: STATUS-VERIFIED
                })
            )
            (map-set volunteers volunteer-id
                (merge volunteer {
                    status: STATUS-SUSPENDED
                })
            )
        )
        
        (ok background-check-passed)
    )
)

(define-public (create-match (volunteer-id uint) (elderly-id uint))
    (let
        (
            (volunteer (unwrap! (get-volunteer volunteer-id) ERR-NOT-FOUND))
            (elderly (unwrap! (get-elderly-participant elderly-id) ERR-NOT-FOUND))
            (match-id (var-get next-match-id))
            (match-score (calculate-match-score volunteer-id elderly-id))
            (current-block-height block-height)
        )
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status volunteer) STATUS-VERIFIED) ERR-INVALID-STATUS)
        (asserts! (is-eq (get status elderly) STATUS-ACTIVE) ERR-INVALID-STATUS)
        (asserts! (is-none (get current-match-id elderly)) ERR-ALREADY-MATCHED)
        (asserts! (>= (get rating volunteer) (var-get minimum-rating)) ERR-INSUFFICIENT-RATING)
        
        (map-set matches match-id
            {
                volunteer-id: volunteer-id,
                elderly-id: elderly-id,
                match-score: match-score,
                created-at: current-block-height,
                status: STATUS-ACTIVE,
                last-interaction: current-block-height,
                safety-checks: u0,
                notes: ""
            }
        )
        
        (map-set volunteers volunteer-id
            (merge volunteer {
                status: STATUS-MATCHED,
                total-matches: (+ (get total-matches volunteer) u1)
            })
        )
        
        (map-set elderly-participants elderly-id
            (merge elderly {
                current-match-id: (some match-id)
            })
        )
        
        (var-set next-match-id (+ match-id u1))
        (ok match-id)
    )
)

(define-public (update-interaction (match-id uint) (notes (string-ascii 500)))
    (let
        (
            (match-data (unwrap! (get-match match-id) ERR-NOT-FOUND))
            (volunteer-id (get volunteer-id match-data))
            (elderly-id (get elderly-id match-data))
            (volunteer-address (unwrap! (map-get? volunteer-addresses volunteer-id) ERR-NOT-FOUND))
            (elderly-address (unwrap! (map-get? elderly-addresses elderly-id) ERR-NOT-FOUND))
            (current-block-height block-height)
        )
        (asserts! (or 
            (is-eq tx-sender volunteer-address)
            (is-eq tx-sender elderly-address)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status match-data) STATUS-ACTIVE) ERR-INVALID-STATUS)
        
        (map-set matches match-id
            (merge match-data {
                last-interaction: current-block-height,
                notes: notes
            })
        )
        
        (ok true)
    )
)

(define-public (rate-volunteer (volunteer-id uint) (rating uint))
    (let
        (
            (volunteer (unwrap! (get-volunteer volunteer-id) ERR-NOT-FOUND))
            (elderly-id (unwrap! (map-get? user-elderly-ids tx-sender) ERR-NOT-AUTHORIZED))
            (elderly (unwrap! (get-elderly-participant elderly-id) ERR-NOT-FOUND))
        )
        (asserts! (<= rating u10) ERR-INVALID-STATUS)
        (asserts! (>= rating u1) ERR-INVALID-STATUS)
        
        (map-set volunteers volunteer-id
            (merge volunteer {
                rating: (/ (+ (* (get rating volunteer) (get total-matches volunteer)) rating) 
                          (+ (get total-matches volunteer) u1))
            })
        )
        
        (ok true)
    )
)

(define-public (end-match (match-id uint) (reason (string-ascii 200)))
    (let
        (
            (match-data (unwrap! (get-match match-id) ERR-NOT-FOUND))
            (volunteer-id (get volunteer-id match-data))
            (elderly-id (get elderly-id match-data))
            (volunteer (unwrap! (get-volunteer volunteer-id) ERR-NOT-FOUND))
            (elderly (unwrap! (get-elderly-participant elderly-id) ERR-NOT-FOUND))
        )
        (asserts! (or
            (is-eq tx-sender (get address volunteer))
            (is-eq tx-sender (get address elderly))
            (is-eq tx-sender (get emergency-contact elderly))
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        
        (map-set matches match-id
            (merge match-data {
                status: "completed",
                notes: reason
            })
        )
        
        (map-set volunteers volunteer-id
            (merge volunteer {
                status: STATUS-VERIFIED
            })
        )
        
        (map-set elderly-participants elderly-id
            (merge elderly {
                current-match-id: none
            })
        )
        
        (ok true)
    )
)

(define-public (emergency-alert (elderly-id uint))
    (let
        (
            (elderly (unwrap! (get-elderly-participant elderly-id) ERR-NOT-FOUND))
            (emergency-contact (get emergency-contact elderly))
        )
        (asserts! (or
            (is-eq tx-sender (get address elderly))
            (is-eq tx-sender emergency-contact)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        
        ;; This would trigger external emergency protocols
        ;; In a full implementation, this would interface with external systems
        (ok true)
    )
)

;; Admin functions
(define-public (set-minimum-rating (new-rating uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rating u10) ERR-INVALID-STATUS)
        (var-set minimum-rating new-rating)
        (ok true)
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)


;; title: companion-matching
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

