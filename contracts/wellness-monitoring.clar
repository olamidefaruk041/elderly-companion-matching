;; Wellness Monitoring Contract
;; Non-intrusive wellness monitoring and check-ins for elderly participants

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-INVALID-INTERVAL (err u204))
(define-constant ERR-EMERGENCY-ACTIVE (err u205))
(define-constant ERR-INVALID-THRESHOLD (err u206))
(define-constant ERR-DUPLICATE-CHECKIN (err u207))
(define-constant ERR-WELLNESS-SCORE-INVALID (err u208))
(define-constant ERR-ALERT-ALREADY-RESOLVED (err u209))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-participant-id uint u1)
(define-data-var next-checkin-id uint u1)
(define-data-var next-alert-id uint u1)
(define-data-var emergency-threshold uint u3)
(define-data-var wellness-check-interval uint u144) ;; blocks (~24 hours)

;; Status constants
(define-constant STATUS-ACTIVE "active")
(define-constant STATUS-INACTIVE "inactive")
(define-constant STATUS-EMERGENCY "emergency")
(define-constant STATUS-RESOLVED "resolved")
(define-constant STATUS-PENDING "pending")
(define-constant ALERT-HIGH "high")
(define-constant ALERT-MEDIUM "medium")
(define-constant ALERT-LOW "low")

;; Wellness score ranges
(define-constant WELLNESS-EXCELLENT u9)
(define-constant WELLNESS-GOOD u7)
(define-constant WELLNESS-FAIR u5)
(define-constant WELLNESS-POOR u3)
(define-constant WELLNESS-CRITICAL u1)

;; Data maps
(define-map wellness-participants
    uint
    {
        address: principal,
        name: (string-ascii 100),
        emergency-contacts: (list 3 principal),
        medical-conditions: (string-ascii 300),
        check-in-frequency: uint,
        last-checkin: uint,
        wellness-score: uint,
        status: (string-ascii 20),
        registered-at: uint,
        total-checkins: uint
    }
)

(define-map wellness-checkins
    uint
    {
        participant-id: uint,
        checkin-time: uint,
        wellness-score: uint,
        mood-rating: uint,
        physical-status: (string-ascii 100),
        notes: (string-ascii 500),
        submitted-by: principal,
        verified: bool
    }
)

(define-map wellness-alerts
    uint
    {
        participant-id: uint,
        alert-type: (string-ascii 20),
        severity: (string-ascii 10),
        description: (string-ascii 300),
        created-at: uint,
        status: (string-ascii 20),
        resolved-at: (optional uint),
        resolved-by: (optional principal),
        response-time: (optional uint)
    }
)

(define-map participant-addresses uint principal)
(define-map user-participant-ids principal uint)
(define-map emergency-contact-links principal (list 5 uint))
(define-map wellness-trends uint (list 30 uint)) ;; Last 30 wellness scores
(define-map checkin-reminders uint uint) ;; participant-id -> next reminder block

;; Read-only functions
(define-read-only (get-participant (participant-id uint))
    (map-get? wellness-participants participant-id)
)

(define-read-only (get-checkin (checkin-id uint))
    (map-get? wellness-checkins checkin-id)
)

(define-read-only (get-alert (alert-id uint))
    (map-get? wellness-alerts alert-id)
)

(define-read-only (get-participant-by-address (address principal))
    (match (map-get? user-participant-ids address)
        participant-id (get-participant participant-id)
        none
    )
)

(define-read-only (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-read-only (calculate-wellness-trend (participant-id uint))
    (let
        (
            (trends (default-to (list) (map-get? wellness-trends participant-id)))
            (trend-length (len trends))
        )
        (if (> trend-length u0)
            (/ (fold + trends u0) trend-length)
            u5
        )
    )
)

(define-read-only (is-emergency-contact (participant-id uint) (contact principal))
    (let
        (
            (participant (unwrap! (get-participant participant-id) false))
            (contacts (get emergency-contacts participant))
        )
        (is-some (index-of contacts contact))
    )
)

(define-read-only (get-overdue-participants)
    (let
        (
            (current-block block-height)
            (check-interval (var-get wellness-check-interval))
        )
        ;; In a full implementation, this would return a list of overdue participants
        ;; For this demo, we return a simple boolean indicating if checks are needed
        (ok (> current-block check-interval))
    )
)

;; Public functions
(define-public (register-participant
    (name (string-ascii 100))
    (emergency-contacts (list 3 principal))
    (medical-conditions (string-ascii 300))
    (check-in-frequency uint)
)
    (let
        (
            (participant-id (var-get next-participant-id))
            (current-block block-height)
        )
        (asserts! (is-none (map-get? user-participant-ids tx-sender)) ERR-ALREADY-EXISTS)
        (asserts! (> check-in-frequency u0) ERR-INVALID-INTERVAL)
        (asserts! (<= check-in-frequency u1000) ERR-INVALID-INTERVAL)
        (asserts! (> (len emergency-contacts) u0) ERR-NOT-FOUND)
        
        (map-set wellness-participants participant-id
            {
                address: tx-sender,
                name: name,
                emergency-contacts: emergency-contacts,
                medical-conditions: medical-conditions,
                check-in-frequency: check-in-frequency,
                last-checkin: current-block,
                wellness-score: u5,
                status: STATUS-ACTIVE,
                registered-at: current-block,
                total-checkins: u0
            }
        )
        
        (map-set participant-addresses participant-id tx-sender)
        (map-set user-participant-ids tx-sender participant-id)
        (map-set checkin-reminders participant-id (+ current-block check-in-frequency))
        (var-set next-participant-id (+ participant-id u1))
        
        (ok participant-id)
    )
)

(define-public (submit-checkin
    (participant-id uint)
    (wellness-score uint)
    (mood-rating uint)
    (physical-status (string-ascii 100))
    (notes (string-ascii 500))
)
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
            (checkin-id (var-get next-checkin-id))
            (current-block block-height)
            (participant-address (get address participant))
        )
        (asserts! (or
            (is-eq tx-sender participant-address)
            (is-emergency-contact participant-id tx-sender)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (<= wellness-score u10) ERR-WELLNESS-SCORE-INVALID)
        (asserts! (>= wellness-score u1) ERR-WELLNESS-SCORE-INVALID)
        (asserts! (<= mood-rating u10) ERR-WELLNESS-SCORE-INVALID)
        (asserts! (>= mood-rating u1) ERR-WELLNESS-SCORE-INVALID)
        
        ;; Record the check-in
        (map-set wellness-checkins checkin-id
            {
                participant-id: participant-id,
                checkin-time: current-block,
                wellness-score: wellness-score,
                mood-rating: mood-rating,
                physical-status: physical-status,
                notes: notes,
                submitted-by: tx-sender,
                verified: (is-eq tx-sender participant-address)
            }
        )
        
        ;; Update participant data
        (map-set wellness-participants participant-id
            (merge participant {
                last-checkin: current-block,
                wellness-score: wellness-score,
                total-checkins: (+ (get total-checkins participant) u1)
            })
        )
        
        
        ;; Set next reminder
        (map-set checkin-reminders participant-id 
            (+ current-block (get check-in-frequency participant)))
        
        ;; Check if alert should be generated
        (if (< wellness-score (var-get emergency-threshold))
            (begin
                (unwrap-panic (create-wellness-alert participant-id "low-wellness" ALERT-HIGH 
                    "Wellness score below emergency threshold"))
                true
            )
            true
        )
        
        (var-set next-checkin-id (+ checkin-id u1))
        (ok checkin-id)
    )
)

(define-public (create-wellness-alert
    (participant-id uint)
    (alert-type (string-ascii 20))
    (severity (string-ascii 10))
    (description (string-ascii 300))
)
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
            (alert-id (var-get next-alert-id))
            (current-block block-height)
        )
        (asserts! (or
            (is-eq tx-sender (get address participant))
            (is-emergency-contact participant-id tx-sender)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        
        (map-set wellness-alerts alert-id
            {
                participant-id: participant-id,
                alert-type: alert-type,
                severity: severity,
                description: description,
                created-at: current-block,
                status: STATUS-PENDING,
                resolved-at: none,
                resolved-by: none,
                response-time: none
            }
        )
        
        ;; Update participant status if high severity
        (if (is-eq severity ALERT-HIGH)
            (begin
                (map-set wellness-participants participant-id
                    (merge participant {
                        status: STATUS-EMERGENCY
                    })
                )
                true
            )
            true
        )
        
        (var-set next-alert-id (+ alert-id u1))
        (ok alert-id)
    )
)

(define-public (resolve-alert (alert-id uint) (resolution-notes (string-ascii 500)))
    (let
        (
            (alert-data (unwrap! (get-alert alert-id) ERR-NOT-FOUND))
            (participant-id (get participant-id alert-data))
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
            (current-block block-height)
            (response-time (- current-block (get created-at alert-data)))
        )
        (asserts! (or
            (is-emergency-contact participant-id tx-sender)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status alert-data) STATUS-PENDING) ERR-ALERT-ALREADY-RESOLVED)
        
        (map-set wellness-alerts alert-id
            (merge alert-data {
                status: STATUS-RESOLVED,
                resolved-at: (some current-block),
                resolved-by: (some tx-sender),
                response-time: (some response-time)
            })
        )
        
        ;; Update participant status back to active if it was emergency
        (if (is-eq (get status participant) STATUS-EMERGENCY)
            (begin
                (map-set wellness-participants participant-id
                    (merge participant {
                        status: STATUS-ACTIVE
                    })
                )
                true
            )
            true
        )
        
        (ok true)
    )
)

(define-public (emergency-intervention (participant-id uint) (intervention-notes (string-ascii 300)))
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
            (current-block block-height)
        )
        (asserts! (or
            (is-emergency-contact participant-id tx-sender)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        
        ;; Create high-priority alert
        (unwrap! (create-wellness-alert participant-id "emergency" 
            ALERT-HIGH intervention-notes) ERR-EMERGENCY-ACTIVE)
        
        ;; Update participant status
        (map-set wellness-participants participant-id
            (merge participant {
                status: STATUS-EMERGENCY,
                last-checkin: current-block
            })
        )
        
        (ok true)
    )
)

(define-public (update-emergency-contacts
    (participant-id uint)
    (new-contacts (list 3 principal))
)
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get address participant)) ERR-NOT-AUTHORIZED)
        (asserts! (> (len new-contacts) u0) ERR-NOT-FOUND)
        
        (map-set wellness-participants participant-id
            (merge participant {
                emergency-contacts: new-contacts
            })
        )
        
        (ok true)
    )
)

(define-public (set-checkin-frequency
    (participant-id uint)
    (new-frequency uint)
)
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
        )
        (asserts! (or
            (is-eq tx-sender (get address participant))
            (is-emergency-contact participant-id tx-sender)
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        (asserts! (> new-frequency u0) ERR-INVALID-INTERVAL)
        (asserts! (<= new-frequency u1000) ERR-INVALID-INTERVAL)
        
        (map-set wellness-participants participant-id
            (merge participant {
                check-in-frequency: new-frequency
            })
        )
        
        ;; Update next reminder
        (map-set checkin-reminders participant-id 
            (+ block-height new-frequency))
        
        (ok true)
    )
)

;; Admin functions
(define-public (set-emergency-threshold (new-threshold uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-threshold u10) ERR-INVALID-THRESHOLD)
        (asserts! (>= new-threshold u1) ERR-INVALID-THRESHOLD)
        (var-set emergency-threshold new-threshold)
        (ok true)
    )
)

(define-public (set-wellness-check-interval (new-interval uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> new-interval u0) ERR-INVALID-INTERVAL)
        (var-set wellness-check-interval new-interval)
        (ok true)
    )
)

(define-public (deactivate-participant (participant-id uint))
    (let
        (
            (participant (unwrap! (get-participant participant-id) ERR-NOT-FOUND))
        )
        (asserts! (or
            (is-eq tx-sender (get address participant))
            (is-contract-owner)
        ) ERR-NOT-AUTHORIZED)
        
        (map-set wellness-participants participant-id
            (merge participant {
                status: STATUS-INACTIVE
            })
        )
        
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


;; title: wellness-monitoring
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

