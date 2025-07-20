;; sync-search-manager.clar
;; Sync Search Tool - Decentralized Search Request and Index Management

;; This contract manages search requests, indexing, and reward mechanisms 
;; on a decentralized search platform using the Stacks blockchain.

;; =============== Error Constants ===============

(define-constant ERR-NOT-AUTHORIZED (err u2001))
(define-constant ERR-SEARCH-GROUP-EXISTS (err u2002))
(define-constant ERR-SEARCH-GROUP-NOT-FOUND (err u2003))
(define-constant ERR-USER-NOT-IN-GROUP (err u2004))
(define-constant ERR-USER-ALREADY-IN-GROUP (err u2005))
(define-constant ERR-REQUEST-NOT-FOUND (err u2006))
(define-constant ERR-INSUFFICIENT-TOKENS (err u2007))
(define-constant ERR-INVALID-AMOUNT (err u2008))
(define-constant ERR-INVALID-ALLOCATION (err u2009))
(define-constant ERR-INVALID-REQUEST-TYPE (err u2010))
(define-constant ERR-GROUP-HAS-ACTIVE-REQUESTS (err u2011))
(define-constant ERR-INVALID-PARAMETER (err u2012))

;; =============== Data Structures ===============

;; Tracks all search groups and their creators
(define-map search-groups
  { group-id: uint }
  { 
    name: (string-ascii 100),
    creator: principal,
    created-at: uint,
    active: bool
  }
)

;; Tracks group membership
(define-map group-members
  { group-id: uint, member: principal }
  {
    joined-at: uint,
    contribution-bps: uint,   ;; Basis points for contribution (100 = 1%, 10000 = 100%)
    active: bool
  }
)

;; Maps group IDs to list of member principals
(define-map group-member-list
  { group-id: uint }
  { members: (list 20 principal) }
)

;; Stores search request information
(define-map search-requests
  { group-id: uint, request-id: uint }
  {
    query: (string-ascii 200),
    reward-amount: uint,
    creator: principal,
    request-type: (string-ascii 20),   ;; "standard" or "priority"
    complexity-score: uint,
    created-at: uint,
    completed: bool
  }
)

;; Tracks member contributions to search requests
(define-map request-contributions
  { group-id: uint, request-id: uint, member: principal }
  { contribution-bps: uint }
)

;; Tracks rewards and settlements for search requests
(define-map request-settlements
  { group-id: uint, request-id: uint }
  {
    total-reward: uint,
    top-contributor: principal,
    settlement-timestamp: uint
  }
)

;; Counter for group IDs
(define-data-var next-group-id uint u1)

;; Counters for request IDs per group
(define-map group-counters
  { group-id: uint }
  { 
    next-request-id: uint
  }
)

;; =============== Private Functions ===============

;; Get the next group ID and increment the counter
(define-private (get-next-group-id)
  (let ((current-id (var-get next-group-id)))
    (var-set next-group-id (+ current-id u1))
    current-id
  )
)

;; Get the next request ID for a group
(define-private (get-next-request-id (group-id uint))
  (let (
    (counters (default-to { next-request-id: u1 } 
                (map-get? group-counters { group-id: group-id })))
    (next-id (get next-request-id counters))
  )
    (map-set group-counters 
      { group-id: group-id } 
      (merge counters { next-request-id: (+ next-id u1) })
    )
    next-id
  )
)

;; Check if a user is a member of a group
(define-private (is-member (group-id uint) (user principal))
  (match (map-get? group-members { group-id: group-id, member: user })
    member (and (get active member) true)
    false
  )
)

;; Check if user is group admin (currently only the creator)
(define-private (is-group-admin (group-id uint) (user principal))
  (match (map-get? search-groups { group-id: group-id })
    group (is-eq (get creator group) user)
    false
  )
)

;; Calculate equal contribution allocation
(define-private (calculate-equal-allocation (group-id uint))
  (match (map-get? group-member-list { group-id: group-id })
    member-list (let ((member-count (len (get members member-list))))
      (if (> member-count u0)
        (/ u10000 member-count)  ;; Equal division (10000 basis points = 100%)
        u0
      ))
    u0
  )
)

;; Add member to the group member list
(define-private (add-to-member-list (group-id uint) (new-member principal))
  (let (
    (current-list-struct (default-to { members: (list) } 
                  (map-get? group-member-list { group-id: group-id })))
    (updated-members-list (unwrap! (as-max-len? (append (get members current-list-struct) new-member) u20) ERR-INVALID-PARAMETER))
  )
    (map-set group-member-list 
      { group-id: group-id } 
      { members: updated-members-list }
    )
    (ok true)
  )
)

;; =============== Read-Only Functions ===============

;; Get search group information
(define-read-only (get-search-group (group-id uint))
  (map-get? search-groups { group-id: group-id })
)

;; Get member information for a group
(define-read-only (get-group-member (group-id uint) (member principal))
  (map-get? group-members { group-id: group-id, member: member })
)

;; Get all members of a group
(define-read-only (get-group-members (group-id uint))
  (map-get? group-member-list { group-id: group-id })
)

;; Get a search request's details
(define-read-only (get-search-request (group-id uint) (request-id uint))
  (map-get? search-requests { group-id: group-id, request-id: request-id })
)

;; Get a member's contribution to a specific request
(define-read-only (get-request-contribution (group-id uint) (request-id uint) (member principal))
  (map-get? request-contributions { group-id: group-id, request-id: request-id, member: member })
)

;; Check if a search group exists
(define-read-only (search-group-exists (group-id uint))
  (is-some (map-get? search-groups { group-id: group-id }))
)

;; =============== Public Functions ===============

;; Create a new search group
(define-public (create-search-group (name (string-ascii 100)))
  (let (
    (group-id (get-next-group-id))
    (caller tx-sender)
    (block-height block-height)
  )
    ;; Set group details
    (map-set search-groups 
      { group-id: group-id }
      { 
        name: name,
        creator: caller,
        created-at: block-height,
        active: true
      }
    )
    
    ;; Initialize counters for this group
    (map-set group-counters
      { group-id: group-id }
      { next-request-id: u1 }
    )
    
    ;; Add creator as first member with 100% contribution
    (map-set group-members
      { group-id: group-id, member: caller }
      {
        joined-at: block-height,
        contribution-bps: u10000,  ;; 100% contribution until more members are added
        active: true
      }
    )
    
    ;; Initialize member list with the creator
    (map-set group-member-list
      { group-id: group-id }
      { members: (list caller) }
    )
    
    (ok group-id)
  )
)

;; Add a member to a search group
(define-public (add-member (group-id uint) (new-member principal))
  (let (
    (caller tx-sender)
    (block-height block-height)
  )
    ;; Verify caller is admin
    (asserts! (is-group-admin group-id caller) ERR-NOT-AUTHORIZED)
    
    ;; Verify group exists
    (asserts! (search-group-exists group-id) ERR-SEARCH-GROUP-NOT-FOUND)
    
    ;; Verify new member isn't already a member
    (asserts! (not (is-member group-id new-member)) ERR-USER-ALREADY-IN-GROUP)
    
    ;; Add member with equal allocation
    (try! (add-to-member-list group-id new-member))
    
    ;; Calculate equal allocation for all members
    (let ((equal-allocation (calculate-equal-allocation group-id)))
      ;; Update all existing members to have equal contribution
      (map-set group-members
        { group-id: group-id, member: new-member }
        {
          joined-at: block-height,
          contribution-bps: equal-allocation,
          active: true
        }
      )
      
      ;; Return success
      (ok true)
    )
  )
)

;; Create a new search request
(define-public (create-search-request 
  (group-id uint) 
  (query (string-ascii 200)) 
  (reward-amount uint)
  (request-type (string-ascii 20))
)
  (let (
    (caller tx-sender)
    (request-id (get-next-request-id group-id))
    (block-height block-height)
  )
    ;; Verify caller is a group member
    (asserts! (is-member group-id caller) ERR-USER-NOT-IN-GROUP)
    
    ;; Verify group exists
    (asserts! (search-group-exists group-id) ERR-SEARCH-GROUP-NOT-FOUND)
    
    ;; Verify reward amount is positive
    (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Verify request type
    (asserts! 
      (or 
        (is-eq request-type "standard") 
        (is-eq request-type "priority")
      ) 
      ERR-INVALID-REQUEST-TYPE
    )
    
    ;; Set search request details
    (map-set search-requests
      { group-id: group-id, request-id: request-id }
      {
        query: query,
        reward-amount: reward-amount,
        creator: caller,
        request-type: request-type,
        complexity-score: u1, ;; Basic complexity score, can be enhanced
        created-at: block-height,
        completed: false
      }
    )
    
    (ok request-id)
  )
)

;; Update a member's contribution percentage
(define-public (update-member-contribution 
  (group-id uint) 
  (member principal) 
  (contribution-bps uint)
)
  (let (
    (caller tx-sender)
  )
    ;; Verify caller is admin
    (asserts! (is-group-admin group-id caller) ERR-NOT-AUTHORIZED)
    
    ;; Verify group exists
    (asserts! (search-group-exists group-id) ERR-SEARCH-GROUP-NOT-FOUND)
    
    ;; Verify member exists in group
    (asserts! (is-member group-id member) ERR-USER-NOT-IN-GROUP)
    
    ;; Verify contribution is valid (0-10000)
    (asserts! (<= contribution-bps u10000) ERR-INVALID-ALLOCATION)
    
    ;; Update member contribution
    (map-set group-members
      { group-id: group-id, member: member }
      {
        joined-at: (unwrap! (get joined-at (get-group-member group-id member)) ERR-USER-NOT-IN-GROUP),
        contribution-bps: contribution-bps,
        active: true
      }
    )
    
    (ok true)
  )
)