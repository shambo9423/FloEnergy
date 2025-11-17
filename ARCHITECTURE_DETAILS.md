# Random User Batch - Architecture & Implementation Details

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

### Phase 1: START METHOD
```
1. Creates HttpRequest to Random User API
2. Sets endpoint: https://randomuser.me/api?results=10
3. Sends GET request
4. Validates HTTP status (200)
5. Logs API response to API_Log__c
6. Parses JSON response
7. Returns List<Object> of users for processing
```

### Phase 2: EXECUTE METHOD (for each batch of records)
```
For each user in scope:
  1. Parse user object
  2. Extract fields:
     - name (first, last)
     - location (street, city, state, country, postcode)
     - email
     - phone
     - cell
  
  3. Create Contact record
     - Map all personal/contact info
     - Set mailing address from location
  
  4. Create Account record
     - Set Name = FirstName + LastName + " Household"
     - Set billing address from location
  
  5. Add to insert lists

After loop:
  1. Insert Accounts first (DML 1)
  2. Query created Accounts for ID mapping
  3. Link Contacts to Accounts by name matching
  4. Insert Contacts with AccountId (DML 2)
  5. Handle DML errors gracefully
  6. Log any exceptions to Exception_Log__c
```

### Phase 3: FINISH METHOD
```
1. Log batch completion
2. Record batch job ID
3. Handle any final cleanup
```

## Class Hierarchy & Dependencies

```
RandomUserBatch
├── Implements: Database.Batchable<Object>
├── Implements: Database.AllowsCallouts
├── Methods
│   ├── start() → calls Http.send()
│   ├── execute() → uses Database.insert()
│   └── finish() → logs completion
└── Dependencies
    ├── APILogger (for API logging)
    ├── ExceptionLogger (for error logging)
    └── Contact, Account (Salesforce objects)

RandomUserBatchUtil
├── Public static methods
├── executeBatch() → calls Database.executeBatch()
├── executeBatch(Integer) → overload with batch size
└── Dependencies
    └── RandomUserBatch

RandomUserBatchTest
├── @isTest private class
├── MockHttpResponse implements HttpCalloutMock
├── Test methods
│   ├── testRandomUserBatchExecution()
│   └── testRandomUserBatchWithMultipleUsers()
└── Dependencies
    └── RandomUserBatch
```

## Data Model

### Contact Object (created by batch)
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

### Account Object (created by batch)
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

### Logging Objects (standard)

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

## Governor Limits Analysis

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

## Error Handling Strategy

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
│  └─ Action: Log to Exception_Log__c, continue processing
│
├─ DML Errors
│  ├─ Required field missing
│  ├─ Validation rule failure
│  └─ Action: Log individual error, continue with next record
│
└─ System Errors
   ├─ Out of memory
   ├─ Unexpected exceptions
   └─ Action: Log to Exception_Log__c
```

## Security Considerations

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

## Performance Optimization

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

## Testing Strategy

### Unit Tests (in RandomUserBatchTest.cls)
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

## Deployment Checklist

- [ ] Verify Contact object has required fields
- [ ] Verify Account object has required fields
- [ ] Verify API_Log__c custom object exists
- [ ] Verify Exception_Log__c custom object exists
- [ ] Deploy RandomUserBatch.cls
- [ ] Deploy RandomUserBatchUtil.cls
- [ ] Deploy RandomUserBatchTest.cls
- [ ] Run test class (expect 100% pass rate)
- [ ] Create/schedule batch execution job
- [ ] Monitor first execution for errors
- [ ] Set up alerts for batch failures

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

**Last Updated:** November 14, 2025
**Version:** 1.0
