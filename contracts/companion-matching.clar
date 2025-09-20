;; Companion Matching Contract
;; Safe matching of elderly with companion volunteers

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_INVALID_STATUS (err u400))
(define-constant ERR_BACKGROUND_CHECK_PENDING (err u402))
(define-constant ERR_INCOMPATIBLE_MATCH (err u403))
(define-constant ERR_MATCH_ALREADY_ACTIVE (err u405))

;; Data Variables
(define-data-var next-volunteer-id uint u1)
(define-data-var next-elderly-id uint u1)
(define-data-var next-match-id uint u1)
(define-data-var contract-active bool true)

;; Data Structures

;; Volunteer Profile
(define-map volunteers
  { volunteer-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    age: uint,
    location: (string-ascii 100),
    interests: (list 5 (string-ascii 50)),
    availability: (string-ascii 200),
    background-check-status: (string-ascii 20),
    verification-date: uint,
    is-active: bool,
    rating: uint,
    matches-completed: uint
  }
)

;; Elderly Profile  
(define-map elderly-participants
  { elderly-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    age: uint,
    location: (string-ascii 100),
    interests: (list 5 (string-ascii 50)),
    care-level: (string-ascii 50),
    emergency-contact: (string-ascii 100),
    medical-notes: (string-ascii 500),
    family-contact: principal,
    is-active: bool
  }
)

;; Match Records
(define-map matches
  { match-id: uint }
  {
    volunteer-id: uint,
    elderly-id: uint,
    match-date: uint,
    status: (string-ascii 20),
    compatibility-score: uint,
    approved-by: principal,
    start-date: uint,
    end-date: (optional uint),
    safety-notes: (string-ascii 300),
    family-approved: bool
  }
)

;; Activity Log
(define-map activity-logs
  { match-id: uint, activity-id: uint }
  {
    date: uint,
    activity-type: (string-ascii 100),
    duration: uint,
    notes: (string-ascii 500),
    reported-by: principal,
    wellness-score: uint
  }
)

;; Safety Incidents
(define-map safety-incidents
  { incident-id: uint }
  {
    match-id: uint,
    reported-by: principal,
    incident-date: uint,
    severity: (string-ascii 20),
    description: (string-ascii 500),
    action-taken: (string-ascii 500),
    resolved: bool
  }
)

;; Lookup Maps
(define-map volunteer-by-principal { principal: principal } { volunteer-id: uint })
(define-map elderly-by-principal { principal: principal } { elderly-id: uint })

;; Read-only Functions

(define-read-only (get-volunteer (volunteer-id uint))
  (map-get? volunteers { volunteer-id: volunteer-id })
)

(define-read-only (get-elderly-participant (elderly-id uint))
  (map-get? elderly-participants { elderly-id: elderly-id })
)

(define-read-only (get-match (match-id uint))
  (map-get? matches { match-id: match-id })
)

(define-read-only (get-volunteer-by-principal (user principal))
  (match (map-get? volunteer-by-principal { principal: user })
    volunteer-record (get-volunteer (get volunteer-id volunteer-record))
    none
  )
)

(define-read-only (get-elderly-by-principal (user principal))
  (match (map-get? elderly-by-principal { principal: user })
    elderly-record (get-elderly-participant (get elderly-id elderly-record))
    none
  )
)

(define-read-only (calculate-compatibility-score (volunteer-interests (list 5 (string-ascii 50))) (elderly-interests (list 5 (string-ascii 50))))
  ;; Simplified compatibility calculation based on list lengths
  (let ((vol-count (len volunteer-interests))
        (elderly-count (len elderly-interests)))
    (if (and (> vol-count u0) (> elderly-count u0))
      u60 ;; Base compatibility score
      u20 ;; Lower compatibility if no interests
    )
  )
)

(define-read-only (is-contract-active)
  (var-get contract-active)
)

(define-read-only (get-next-volunteer-id)
  (var-get next-volunteer-id)
)

(define-read-only (get-next-elderly-id)
  (var-get next-elderly-id)
)

;; Public Functions

;; Register as a volunteer
(define-public (register-volunteer 
  (name (string-ascii 100))
  (age uint)
  (location (string-ascii 100))
  (interests (list 5 (string-ascii 50)))
  (availability (string-ascii 200)))
  
  (let ((volunteer-id (var-get next-volunteer-id)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? volunteer-by-principal { principal: tx-sender })) ERR_ALREADY_EXISTS)
    
    (map-set volunteers
      { volunteer-id: volunteer-id }
      {
        principal: tx-sender,
        name: name,
        age: age,
        location: location,
        interests: interests,
        availability: availability,
        background-check-status: "pending",
        verification-date: u0,
        is-active: false,
        rating: u0,
        matches-completed: u0
      }
    )
    
    (map-set volunteer-by-principal { principal: tx-sender } { volunteer-id: volunteer-id })
    (var-set next-volunteer-id (+ volunteer-id u1))
    (ok volunteer-id)
  )
)

;; Register elderly participant
(define-public (register-elderly-participant
  (name (string-ascii 100))
  (age uint)
  (location (string-ascii 100))
  (interests (list 5 (string-ascii 50)))
  (care-level (string-ascii 50))
  (emergency-contact (string-ascii 100))
  (medical-notes (string-ascii 500))
  (family-contact principal))
  
  (let ((elderly-id (var-get next-elderly-id)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? elderly-by-principal { principal: tx-sender })) ERR_ALREADY_EXISTS)
    
    (map-set elderly-participants
      { elderly-id: elderly-id }
      {
        principal: tx-sender,
        name: name,
        age: age,
        location: location,
        interests: interests,
        care-level: care-level,
        emergency-contact: emergency-contact,
        medical-notes: medical-notes,
        family-contact: family-contact,
        is-active: true
      }
    )
    
    (map-set elderly-by-principal { principal: tx-sender } { elderly-id: elderly-id })
    (var-set next-elderly-id (+ elderly-id u1))
    (ok elderly-id)
  )
)

;; Approve volunteer background check (admin only)
(define-public (approve-volunteer-background-check (volunteer-id uint))
  (let ((volunteer-data (unwrap! (map-get? volunteers { volunteer-id: volunteer-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set volunteers
      { volunteer-id: volunteer-id }
      (merge volunteer-data {
        background-check-status: "approved",
        verification-date: block-height,
        is-active: true
      })
    )
    (ok true)
  )
)

;; Create a match between volunteer and elderly participant
(define-public (create-match (volunteer-id uint) (elderly-id uint) (safety-notes (string-ascii 300)))
  (let (
    (match-id (var-get next-match-id))
    (volunteer-data (unwrap! (map-get? volunteers { volunteer-id: volunteer-id }) ERR_NOT_FOUND))
    (elderly-data (unwrap! (map-get? elderly-participants { elderly-id: elderly-id }) ERR_NOT_FOUND))
    (compatibility-score (calculate-compatibility-score 
      (get interests volunteer-data) 
      (get interests elderly-data)))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get background-check-status volunteer-data) "approved") ERR_BACKGROUND_CHECK_PENDING)
    (asserts! (get is-active volunteer-data) ERR_INVALID_STATUS)
    (asserts! (get is-active elderly-data) ERR_INVALID_STATUS)
    (asserts! (>= compatibility-score u40) ERR_INCOMPATIBLE_MATCH) ;; Require at least 40% compatibility
    
    (map-set matches
      { match-id: match-id }
      {
        volunteer-id: volunteer-id,
        elderly-id: elderly-id,
        match-date: block-height,
        status: "pending",
        compatibility-score: compatibility-score,
        approved-by: tx-sender,
        start-date: u0,
        end-date: none,
        safety-notes: safety-notes,
        family-approved: false
      }
    )
    
    (var-set next-match-id (+ match-id u1))
    (ok match-id)
  )
)

;; Family approval for match
(define-public (approve-match-by-family (match-id uint))
  (let ((match-data (unwrap! (map-get? matches { match-id: match-id }) ERR_NOT_FOUND))
        (elderly-data (unwrap! (map-get? elderly-participants { elderly-id: (get elderly-id match-data) }) ERR_NOT_FOUND)))
    
    (asserts! (is-eq tx-sender (get family-contact elderly-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status match-data) "pending") ERR_INVALID_STATUS)
    
    (map-set matches
      { match-id: match-id }
      (merge match-data {
        family-approved: true,
        status: "approved",
        start-date: block-height
      })
    )
    (ok true)
  )
)

;; End a match
(define-public (end-match (match-id uint) (reason (string-ascii 200)))
  (let ((match-data (unwrap! (map-get? matches { match-id: match-id }) ERR_NOT_FOUND))
        (volunteer-data (unwrap! (map-get? volunteers { volunteer-id: (get volunteer-id match-data) }) ERR_NOT_FOUND))
        (elderly-data (unwrap! (map-get? elderly-participants { elderly-id: (get elderly-id match-data) }) ERR_NOT_FOUND)))
    
    (asserts! (or 
      (is-eq tx-sender (get principal volunteer-data))
      (is-eq tx-sender (get principal elderly-data))
      (is-eq tx-sender (get family-contact elderly-data))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_NOT_AUTHORIZED)
    
    (asserts! (is-eq (get status match-data) "approved") ERR_INVALID_STATUS)
    
    (map-set matches
      { match-id: match-id }
      (merge match-data {
        status: "completed",
        end-date: (some block-height)
      })
    )
    
    ;; Update volunteer's completed matches count
    (map-set volunteers
      { volunteer-id: (get volunteer-id match-data) }
      (merge volunteer-data {
        matches-completed: (+ (get matches-completed volunteer-data) u1)
      })
    )
    
    (ok true)
  )
)

;; Emergency functions
(define-public (emergency-suspend-match (match-id uint) (reason (string-ascii 300)))
  (let ((match-data (unwrap! (map-get? matches { match-id: match-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set matches
      { match-id: match-id }
      (merge match-data {
        status: "suspended",
        end-date: (some block-height)
      })
    )
    (ok true)
  )
)

;; Admin functions
(define-public (toggle-contract-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active))
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

