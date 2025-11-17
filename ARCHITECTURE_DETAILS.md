# Architecture & Implementation Details

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SALESFORCE ORG                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              CustomerDetailsQueuable (Global Batch)                 │
│  implements Database.Batchable<Object>                      │
│  implements Database.AllowsCallouts                         │
└─────────────────────────────────────────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
    ┌─────────┐          ┌─────────┐         ┌─────────┐
    │  START  │          │ EXECUTE │         │ FINISH  │
    │ METHOD  │          │ METHOD  │         │ METHOD  │
    └─────────┘          └─────────┘         └─────────┘
        │                    │                    │
        │ Calls API          │ Process Data       │ Finalize
        │ Fetch  users     │ Create Records     │ Logging
        │                    │ Link Objects       │
        ▼                    ▼                    ▼
    ┌──────────────────────────────────────────────────────┐
    │           EXECUTION FLOW                             │
    └──────────────────────────────────────────────────────┘
```

## Detailed Execution Flow

### API Callouts and UserDetailsService
```
1. Creates HttpRequest to the configured external API (example endpoint used during development: https://randomuser.me/api/?nat=us&inc=name,email,phone&noinfo)
2. Sends GET request and validates HTTP status (expect 200)
3. Logs API response to `API_Log__c` using `APILogger` (response body stored for audit)
4. Parses JSON response and returns structured DTOs for downstream processing
```

### Subscription flow (Opportunity-driven)
```
- Trigger: `OpportunityTrigger` (after update) routes to `OpportunitySubscriptionHandler`
- When Opportunity Stage = "Closed Won" and `Add_subscriptions__c` indicates >0, the handler:
   - Builds N `Subscription__c` records (Sequence__c = 1..N)
   - Sets `Opportunity__c`, `Opportunity_Name__c`, `Start_Date__c` (Opportunity CloseDate), `End_Date__c` = CloseDate + 12 months, `Amount__c`, `Status__c`
   - Uses `Database.insert(subscriptions, false)` to allow partial success
   - Collects per-Opportunity errors from `SaveResult` and creates `Exception_Log__c` records in a batch (no logging inside loops)
   - Does NOT add `addError()` for DML failures (to avoid rolling back successful inserts)
   - Account is derived via `Opportunity__r.AccountId` where needed (no Account__c on Subscription)
```

### Finish / cleanup
```
1. Log completion and any summary metrics as needed (via `APILogger` / `ExceptionLogger`)
2. Surface errors in `Exception_Log__c` for operators to review
```

## Class Hierarchy & Dependencies (summary)

Key Apex classes and handlers (high-level):

- `APILogger` — central API logging utility that inserts `API_Log__c` records for all HTTP callouts (stores endpoint, request, response body, status).

- `ExceptionLogger` — centralized exception logging. Supports creating in-memory instances and batched insert pattern so logs are inserted outside of tight loops.

- `UserDetailsService` — performs `HttpRequest` callouts and returns parsed DTOs. Uses `APILogger` for response logging.

- `OpportunitySubscriptionHandler` — trigger handler that creates `Subscription__c` records when Opportunities are marked Won. Uses partial DML and batched exception logging.

- `SubscriptionController` — Apex @AuraEnabled controller used by LWC `subscriptionTable` to query subscriptions for an Account with server-side pagination and optional Status filter.

- LWC `subscriptionTable` — Lightning Web Component showing `Subscription__c` records for an Account. Uses `@api recordId` (page context) and a `lightning-datatable` with pagination and status filtering.

## Data Model (high-level)

### Subscription__c (custom object)
Fields & purpose:
- `Name` (AutoNumber) — e.g., SUB01
- `Opportunity__c` (Lookup[Opportunity]) — reference to originating Opportunity
- `Opportunity_Name__c` (Text) — denormalized Opportunity name for display
- `Start_Date__c` (Date) — typically Opportunity CloseDate
- `End_Date__c` (Date) — Start_Date__c + 12 months (handler sets this)
- `Amount__c` (Currency)
- `Status__c` (Picklist) — Active / Inactive
- `Sequence__c` (Number) — sequence index when multiple subscriptions created from a single Opportunity

Notes:
- `Account` is not stored on `Subscription__c` (derivable via `Opportunity__r.AccountId`)
- Name numbering and Sequence__c ensure unique readable identifiers and ordering
```
Field                  Type        Source
─────────────────────────────────────────────────
FirstName             String      name.first
LastName              String      name.last
Email                 Email       email
Phone                 Phone       phone
MobilePhone           Phone       cell
MailingStreet         String      street number + name
MailingCity           String      location.city
MailingState          String      location.state
MailingCountry        String      location.country
MailingPostalCode     String      location.postcode
AccountId             Lookup      (linked to Account)
```

### API_Log__c (custom object)
Fields & purpose:
- `Timestamp__c` (DateTime)
- `API_Endpoint__c` (Text)
-  `Request_Body__c` (LongText)
- `Response_Body__c` (LongText) — full raw JSON stored for audit
- `Status__c` (Text/Picklist) — Success / Error
- `Error_Message__c` (LongText) — parse or network error details

Purpose: audit trail of all external HTTP callouts and responses. Populated by `APILogger`.
```
Field                  Type        Value
─────────────────────────────────────────────────
Name                  String      {FirstName} {LastName} Household
BillingStreet         String      street number + name
BillingCity           String      location.city
BillingState          String      location.state
BillingCountry        String      location.country
BillingPostalCode     String      location.postcode
Phone                 Phone       phone
Type                  Picklist    (not set)
Industry              Picklist    (not set)
```

### Exception_Log__c (custom object)
Fields & purpose:
- `Timestamp__c` (DateTime)
- `Source__c` (Text) — class/method that raised the exception
- `Record_Id__c` (Text) — related record Id if applicable
- `Exception_Type__c` (Text)
- `Exception_Message__c` (LongText)
- `Stack_Trace__c` (LongText)
- `Context_Data__c` (LongText) — serialized context (e.g., input payload)

Purpose: centralized error and exception capturing. `ExceptionLogger` supports pre-creating instances and batch inserting them to avoid DML inside loops.

**API_Log__c**
```
Field              Type       Value
──────────────────────────────────────
Timestamp__c       DateTime   System.now()
API_Endpoint__c    String     API endpoint URL
Request_Body__c  String     Request Body
Response_Body__c   String     Full API response
Status__c          String     'Success' or 'Error'
Error_Message__c   String     Error details (if any)
```

**Exception_Log__c**
```
Field              Type       Value
──────────────────────────────────────
Timestamp__c       DateTime   System.now()
Source__c          String     Method that threw exception
Exception_Type__c  String     Exception type name
Exception_Message__c String   Exception message
Stack_Trace__c     String     Full stack trace
Context_Data__c    String     Additional context
Record_Id__c       String     Related record ID (if any)
```

## Runtime & Integration Notes

### Per Batch Execution
```
Operation                    Used    Limit   Status
─────────────────────────────────────────────────
Heap Size                    ~2MB    6MB     ✓ Safe
API Callouts                 1       100     ✓ Safe
DML Statements               2       150     ✓ Safe
Database Insert Operations   2       10,000  ✓ Safe
SOQL Queries                 1       100     ✓ Safe
Records Processed            10      10,000  ✓ Safe
```

## Error Handling Strategy (updated)

```
┌─ API Callout Errors
│  ├─ Non-200 status
│  ├─ Network timeout
│  ├─ Invalid JSON
│  └─ Action: Log to API_Log__c, throw CalloutException
│
├─ Data Processing Errors
│  ├─ Missing fields
│  ├─ Type conversion errors
│  └─ Action: Collect error details and create `Exception_Log__c` entries in-memory, then batch-insert after processing (no per-record DML inside loops)
│
├─ DML Errors
│  ├─ Required field missing
│  ├─ Validation rule failure
│  └─ Action for Subscription creation: use `Database.insert(list, false)` to allow partial success; collect `Database.SaveResult` messages and convert to `Exception_Log__c` entries after DML
│
└─ System Errors
   ├─ Out of memory
   ├─ Unexpected exceptions
   └─ Action: Log to Exception_Log__c
```

## LWC: `subscriptionTable` (UI details)

- Placed on Account record page (Lightning App Builder). Component uses `@api recordId` to receive the Account Id from the page context.
- Displays `Subscription__c` records related to the Account via `Opportunity__r.AccountId` (server-side query in `SubscriptionController`).
- Uses `lightning-datatable` for columns: Name, Opportunity Name, Start Date, End Date, Amount (currency), Status, Sequence
- Pagination: server-side, `perPage = 10` default, `page` navigation with Previous/Next; `pageInfo` shows current range and total
- Filtering: Status combobox (All / Active / Inactive)
- Error handling: `ShowToastEvent` used to surface Apex errors; component avoids requiring manual setup (`recordId` injected by platform)

### Data Access Control
- `with sharing` keyword ensures user permissions are respected
- Contact/Account creation respects user's create permissions

### API Security
- Uses secure HTTPS endpoint
- Timeout set to 120 seconds (prevents hanging)
- Validates HTTP response before processing

### Data Privacy
- No sensitive data is logged beyond what's needed for troubleshooting
- Exception logs contain necessary context for debugging
- API logs store full response for audit purposes

## Metadata & Deployment Notes

- Metadata reorganization: custom objects were migrated to Salesforce DX style with `*.object-meta.xml` files and individual field files under `objects/<ObjectName>/fields/*.field-meta.xml`.
- Legacy files with `.object` extension may still exist in the workspace and should be removed before deployment to avoid duplicate metadata errors.
- Several Apex class meta files updated: `APILogger.cls-meta.xml`, `ExceptionLogger.cls-meta.xml`, `SubscriptionController.cls-meta.xml` etc.

Deployment checklist (updated):
- Delete legacy `Subscription__c.object`, `Subscription__c-meta.xml`, `API_Log__c.object`, `API_Log__c-meta.xml`, `Exception_Log__c.object`, `Exception_Log__c-meta.xml` from the repo/workspace prior to SFDX deploy (cannot be safely deployed as duplicates).
- Run `sfdx force:source:deploy -p force-app/main/default` (or use VS Code SFDX commands) and inspect compile errors.
- Ensure test classes exist for callouts (HttpCalloutMock) and for `OpportunitySubscriptionHandler`.

### Database Optimization
```apex
// Accounts inserted first for ID availability
Database.insert(accountsToInsert, false);

// Single query to fetch all account IDs (not individual lookups)
Map<String, Id> accountNameToIdMap = new Map<String, Id>();

// Batch contacts by 10 for efficient processing
executeBatch(batch, 10);
```

### API Optimization
```apex
// Single callout per batch execution (in start method)
// Fetches 10 records at once (not individual requests)
// Reuses Http connection object
```

## Execution Scenarios

### Scenario 1: Manual Execution from Execute Anonymous
```apex
// User executes
Id jobId = CustomerDetailsQueuable.executeBatch();

// Results
✓ 10 Contacts created
✓ 10 Accounts created (Household)
✓ 10 Contact-Account relationships established
✓ API response logged
✓ Execution time: ~30 seconds
```

### Scenario 2: Scheduled Daily Execution
```apex
// Setup
System.schedule('Daily Random Users', '0 0 2 * * ?', new CustomerDetailsQueuable());

// Daily execution at 2 AM
// Creates ~3,650 records per year (10 × 365)
// Separate batch jobs, separate logs
```

### Scenario 3: Error Scenario
```apex
// If API returns 400 error
✓ APILogger records the error
✓ Batch aborts gracefully
✓ No records created
✓ User can see error in API_Log__c

// If single Contact has invalid phone
✓ Contact insert fails for that record
✓ Error logged to Exception_Log__c
✓ Batch continues with next Contact
✓ Other records successfully created
```

## Testing Strategy (next steps)

Planned/Needed tests:
- Add `HttpCalloutMock`-based tests for `UserDetailsService` to verify APILogger integration and response parsing.
- Add unit tests for `OpportunitySubscriptionHandler` to validate:
   - Correct number of `Subscription__c` records created for various `Add_subscriptions__c` values
   - `Sequence__c` ordering
   - Partial DML behavior and creation of `Exception_Log__c` entries on failures
- Add tests verifying `ExceptionLogger` batch-create pattern and that no DML occurs inside loops.
```
1. MockHttpResponse - Simulates API responses
2. Test 1: Basic execution flow
   - Verifies batch completes
   - Verifies Contact created with correct data
   - Verifies Account created with Household naming
   - Verifies Contact-Account relationship

3. Test 2: Multiple records processing
   - Verifies batch handles multiple users
   - Verifies all records processed
```

### Integration Testing (Manual)
```
1. Run batch from Execute Anonymous
2. Query API_Log__c for errors
3. Verify Contacts and Accounts created
4. Check Contact-Account relationships
5. Verify address data accuracy
```

## Deployment Checklist (summary)

- [ ] Verify Contact object has required fields (if RandomUser batch is used)
- [ ] Verify `API_Log__c`, `Exception_Log__c`, and `Subscription__c` custom objects exist (use DX metadata)
- [ ] Remove legacy `.object` metadata files from the repo before deploy
- [ ] Deploy all Apex classes and LWC (`subscriptionTable`) via SFDX or CI pipeline
- [ ] Run unit tests (include callout mocks) and reach required coverage
- [ ] Validate component on Account record page and test `recordId` context

## Maintenance & Monitoring

### Regular Monitoring
```
Weekly:
- Check API_Log__c for API errors
- Check Exception_Log__c for processing errors
- Verify Contact/Account counts increase

Monthly:
- Review error trends
- Validate data accuracy
- Check storage usage
```

### Common Issues & Solutions

| Issue | Root Cause | Solution |
|-------|-----------|----------|
| "Invalid JSON" | API response changed | Update parsing logic |
| "Required fields missing" | Missing Contact fields | Add field mappings |
| "Duplicate records" | No duplicate handling | Add deduplication logic |
| "Batch queued forever" | Concurrency limit | Schedule batch during off-peak |

---

**Last Updated:** November 17, 2025
**Version:** 1.1
