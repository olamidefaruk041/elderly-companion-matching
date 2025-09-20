;; Wellness Monitoring Contract
;; Non-intrusive wellness monitoring and check-ins

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_INVALID_DATA (err u400))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_EMERGENCY_ACTIVE (err u503))
(define-constant ERR_SCHEDULE_CONFLICT (err u405))
(define-constant ERR_OVERDUE_CHECKIN (err u408))

;; Wellness status constants
(define-constant WELLNESS_EXCELLENT u5)
(define-constant WELLNESS_GOOD u4)
(define-constant WELLNESS_FAIR u3)
(define-constant WELLNESS_POOR u2)
(define-constant WELLNESS_CRITICAL u1)

;; Alert severity levels
(define-constant ALERT_INFO u1)
(define-constant ALERT_WARNING u2)
(define-constant ALERT_URGENT u3)
(define-constant ALERT_EMERGENCY u4)

;; Data Variables
(define-data-var next-participant-id uint u1)
(define-data-var next-checkin-id uint u1)
(define-data-var next-alert-id uint u1)
(define-data-var next-schedule-id uint u1)
(define-data-var contract-active bool true)
(define-data-var emergency-mode bool false)

;; Data Structures

;; Participant Wellness Profile
(define-map wellness-participants
  { participant-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    age: uint,
    emergency-contacts: (list 3 (string-ascii 100)),
    medical-conditions: (list 5 (string-ascii 100)),
    medications: (list 10 (string-ascii 100)),
    baseline-vitals: {
      heart-rate: uint,
      blood-pressure-sys: uint,
      blood-pressure-dia: uint,
      weight: uint,
      mobility-score: uint
    },
    care-team: (list 3 principal),
    family-contacts: (list 5 principal),
    last-checkin: uint,
    wellness-score: uint,
    is-active: bool,
    privacy-level: uint
  }
)

;; Daily Wellness Check-ins
(define-map wellness-checkins
  { checkin-id: uint }
  {
    participant-id: uint,
    checkin-date: uint,
    reported-by: principal,
    wellness-score: uint,
    mood-rating: uint,
    physical-activity: (string-ascii 200),
    sleep-quality: uint,
    appetite-level: uint,
    pain-level: uint,
    medication-compliance: bool,
    social-interaction: (string-ascii 200),
    concerns: (string-ascii 500),
    vitals: {
      heart-rate: uint,
      blood-pressure-sys: uint,
      blood-pressure-dia: uint,
      weight: uint,
      temperature: uint
    },
    notes: (string-ascii 1000),
    verified-by-caregiver: bool
  }
)

;; Health Alerts & Notifications
(define-map health-alerts
  { alert-id: uint }
  {
    participant-id: uint,
    alert-type: (string-ascii 50),
    severity: uint,
    triggered-date: uint,
    description: (string-ascii 500),
    triggered-by: principal,
    related-checkin: (optional uint),
    action-required: (string-ascii 300),
    resolved: bool,
    resolved-by: (optional principal),
    resolved-date: (optional uint),
    family-notified: bool,
    emergency-services-called: bool
  }
)

;; Wellness Check Schedules
(define-map wellness-schedules
  { schedule-id: uint }
  {
    participant-id: uint,
    schedule-type: (string-ascii 50),
    frequency: uint, ;; hours between checks
    next-due: uint,
    assigned-caregiver: principal,
    backup-caregiver: (optional principal),
    is-active: bool,
    created-by: principal,
    special-instructions: (string-ascii 500)
  }
)

;; Family Notifications
(define-map family-notifications
  { participant-id: uint, notification-id: uint }
  {
    family-member: principal,
    notification-type: (string-ascii 50),
    message: (string-ascii 500),
    sent-date: uint,
    read: bool,
    urgency: uint
  }
)

;; Health Trends & Analytics
(define-map wellness-trends
  { participant-id: uint, date: uint }
  {
    average-wellness-score: uint,
    checkin-frequency: uint,
    alert-count: uint,
    improvement-trend: int, ;; positive for improving, negative for declining
    risk-assessment: uint,
    recommendations: (list 5 (string-ascii 100))
  }
)

;; Lookup Maps
(define-map participant-by-principal { principal: principal } { participant-id: uint })

;; Read-only Functions

(define-read-only (get-participant (participant-id uint))
  (map-get? wellness-participants { participant-id: participant-id })
)

(define-read-only (get-checkin (checkin-id uint))
  (map-get? wellness-checkins { checkin-id: checkin-id })
)

(define-read-only (get-alert (alert-id uint))
  (map-get? health-alerts { alert-id: alert-id })
)

(define-read-only (get-participant-by-principal (user principal))
  (match (map-get? participant-by-principal { principal: user })
    participant-record (get-participant (get participant-id participant-record))
    none
  )
)

(define-read-only (calculate-wellness-score (mood uint) (physical uint) (sleep uint) (appetite uint) (pain uint))
  (let ((base-score (+ mood physical sleep appetite)))
    ;; Pain reduces the score
    (if (> pain u0)
      (- base-score pain)
      base-score
    )
  )
)

(define-read-only (assess-risk-level (wellness-score uint) (age uint) (condition-count uint))
  (let ((age-factor (if (>= age u80) u2 (if (>= age u65) u1 u0)))
        (condition-factor (* condition-count u1))
        (wellness-factor (- u6 wellness-score)))
    (+ age-factor condition-factor wellness-factor)
  )
)

(define-read-only (is-checkin-overdue (participant-id uint) (current-time uint))
  (match (get-participant participant-id)
    participant-data
      (let ((last-checkin (get last-checkin participant-data)))
        (> (- current-time last-checkin) u86400) ;; 24 hours in seconds
      )
    false
  )
)

(define-read-only (get-next-participant-id)
  (var-get next-participant-id)
)

(define-read-only (is-emergency-mode)
  (var-get emergency-mode)
)

;; Public Functions

;; Register participant for wellness monitoring
(define-public (register-participant
  (name (string-ascii 100))
  (age uint)
  (emergency-contacts (list 3 (string-ascii 100)))
  (medical-conditions (list 5 (string-ascii 100)))
  (medications (list 10 (string-ascii 100)))
  (baseline-vitals {
    heart-rate: uint,
    blood-pressure-sys: uint,
    blood-pressure-dia: uint,
    weight: uint,
    mobility-score: uint
  })
  (care-team (list 3 principal))
  (family-contacts (list 5 principal)))
  
  (let ((participant-id (var-get next-participant-id)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? participant-by-principal { principal: tx-sender })) ERR_ALREADY_EXISTS)
    
    (map-set wellness-participants
      { participant-id: participant-id }
      {
        principal: tx-sender,
        name: name,
        age: age,
        emergency-contacts: emergency-contacts,
        medical-conditions: medical-conditions,
        medications: medications,
        baseline-vitals: baseline-vitals,
        care-team: care-team,
        family-contacts: family-contacts,
        last-checkin: block-height,
        wellness-score: u3, ;; Default fair score
        is-active: true,
        privacy-level: u2 ;; Default moderate privacy
      }
    )
    
    (map-set participant-by-principal { principal: tx-sender } { participant-id: participant-id })
    (var-set next-participant-id (+ participant-id u1))
    (ok participant-id)
  )
)

;; Submit daily wellness check-in
(define-public (submit-wellness-checkin
  (participant-id uint)
  (mood-rating uint)
  (physical-activity (string-ascii 200))
  (sleep-quality uint)
  (appetite-level uint)
  (pain-level uint)
  (medication-compliance bool)
  (social-interaction (string-ascii 200))
  (concerns (string-ascii 500))
  (vitals {
    heart-rate: uint,
    blood-pressure-sys: uint,
    blood-pressure-dia: uint,
    weight: uint,
    temperature: uint
  })
  (notes (string-ascii 1000)))
  
  (let (
    (checkin-id (var-get next-checkin-id))
    (participant-data (unwrap! (map-get? wellness-participants { participant-id: participant-id }) ERR_NOT_FOUND))
    (wellness-score (calculate-wellness-score mood-rating u5 sleep-quality appetite-level pain-level))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active participant-data) ERR_INVALID_DATA)
    
    ;; Validate input ranges
    (asserts! (and (<= mood-rating u5) (>= mood-rating u1)) ERR_INVALID_DATA)
    (asserts! (and (<= sleep-quality u5) (>= sleep-quality u1)) ERR_INVALID_DATA)
    (asserts! (and (<= appetite-level u5) (>= appetite-level u1)) ERR_INVALID_DATA)
    (asserts! (and (<= pain-level u5) (>= pain-level u0)) ERR_INVALID_DATA)
    
    (map-set wellness-checkins
      { checkin-id: checkin-id }
      {
        participant-id: participant-id,
        checkin-date: block-height,
        reported-by: tx-sender,
        wellness-score: wellness-score,
        mood-rating: mood-rating,
        physical-activity: physical-activity,
        sleep-quality: sleep-quality,
        appetite-level: appetite-level,
        pain-level: pain-level,
        medication-compliance: medication-compliance,
        social-interaction: social-interaction,
        concerns: concerns,
        vitals: vitals,
        notes: notes,
        verified-by-caregiver: false
      }
    )
    
    ;; Update participant's last checkin and wellness score
    (map-set wellness-participants
      { participant-id: participant-id }
      (merge participant-data {
        last-checkin: block-height,
        wellness-score: wellness-score
      })
    )
    
    ;; Check if alert needs to be generated
    (if (or (<= wellness-score u2) (>= pain-level u4))
      (unwrap! (create-health-alert participant-id "low-wellness" ALERT_WARNING 
        "Wellness score or pain level indicates concern" (some checkin-id)) (err u500))
      u0
    )
    
    (var-set next-checkin-id (+ checkin-id u1))
    (ok checkin-id)
  )
)

;; Create health alert
(define-public (create-health-alert
  (participant-id uint)
  (alert-type (string-ascii 50))
  (severity uint)
  (description (string-ascii 500))
  (related-checkin (optional uint)))
  
  (let (
    (alert-id (var-get next-alert-id))
    (participant-data (unwrap! (map-get? wellness-participants { participant-id: participant-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (and (<= severity u4) (>= severity u1)) ERR_INVALID_DATA)
    
    (map-set health-alerts
      { alert-id: alert-id }
      {
        participant-id: participant-id,
        alert-type: alert-type,
        severity: severity,
        triggered-date: block-height,
        description: description,
        triggered-by: tx-sender,
        related-checkin: related-checkin,
        action-required: (if (>= severity ALERT_URGENT) "Immediate attention required" "Monitor closely"),
        resolved: false,
        resolved-by: none,
        resolved-date: none,
        family-notified: false,
        emergency-services-called: false
      }
    )
    
    ;; Auto-notify family for urgent or emergency alerts
    (if (>= severity ALERT_URGENT)
      (try! (notify-family-members participant-id alert-type description severity))
      true
    )
    
    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)
  )
)

;; Notify family members
(define-private (notify-family-members
  (participant-id uint)
  (alert-type (string-ascii 50))
  (message (string-ascii 500))
  (urgency uint))
  
  (let ((participant-data (unwrap! (map-get? wellness-participants { participant-id: participant-id }) ERR_NOT_FOUND)))
    ;; This is a simplified notification - in a real system, this would trigger external notifications
    (ok true)
  )
)

;; Schedule wellness checks
(define-public (schedule-wellness-check
  (participant-id uint)
  (schedule-type (string-ascii 50))
  (frequency uint)
  (assigned-caregiver principal)
  (special-instructions (string-ascii 500)))
  
  (let (
    (schedule-id (var-get next-schedule-id))
    (participant-data (unwrap! (map-get? wellness-participants { participant-id: participant-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (> frequency u0) ERR_INVALID_DATA)
    
    (map-set wellness-schedules
      { schedule-id: schedule-id }
      {
        participant-id: participant-id,
        schedule-type: schedule-type,
        frequency: frequency,
        next-due: (+ block-height frequency),
        assigned-caregiver: assigned-caregiver,
        backup-caregiver: none,
        is-active: true,
        created-by: tx-sender,
        special-instructions: special-instructions
      }
    )
    
    (var-set next-schedule-id (+ schedule-id u1))
    (ok schedule-id)
  )
)

;; Resolve health alert
(define-public (resolve-health-alert (alert-id uint) (resolution-notes (string-ascii 500)))
  (let ((alert-data (unwrap! (map-get? health-alerts { alert-id: alert-id }) ERR_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (not (get resolved alert-data)) ERR_INVALID_DATA)
    
    (map-set health-alerts
      { alert-id: alert-id }
      (merge alert-data {
        resolved: true,
        resolved-by: (some tx-sender),
        resolved-date: (some block-height)
      })
    )
    (ok true)
  )
)

;; Emergency functions
(define-public (declare-emergency (participant-id uint) (emergency-type (string-ascii 50)))
  (let ((participant-data (unwrap! (map-get? wellness-participants { participant-id: participant-id }) ERR_NOT_FOUND)))
    ;; Only authorized care team members or family can declare emergency
    (asserts! (or 
      (is-some (index-of (get care-team participant-data) tx-sender))
      (is-some (index-of (get family-contacts participant-data) tx-sender))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_NOT_AUTHORIZED)
    
    (try! (create-health-alert participant-id emergency-type ALERT_EMERGENCY 
      "Emergency declared - immediate response required" none))
    
    (var-set emergency-mode true)
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

(define-public (clear-emergency-mode)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set emergency-mode false)
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

