# Random User Batch - Visual Reference Guide

## 🗂️ Project Structure

```
FloEnergyTask/
│
├── force-app/main/default/classes/
│   ├── RandomUserBatch.cls ......................... Main batch class (231 lines)
│   ├── RandomUserBatch.cls-meta.xml
│   ├── RandomUserBatchUtil.cls ..................... Utility class (41 lines)
│   ├── RandomUserBatchUtil.cls-meta.xml
│   ├── RandomUserBatchTest.cls ..................... Test class (108 lines)
│   ├── RandomUserBatchTest.cls-meta.xml
│   │
│   ├── APILogger.cls .............................. [Existing] API logging
│   ├── ExceptionLogger.cls ......................... [Existing] Exception logging
│   ├── UserDetailsService.cls ...................... [Existing]
│   └── [other classes]
│
├── scripts/apex/
│   ├── randomuser_batch_execution.apex ............ Execution examples
│   └── hello.apex ................................. [Existing]
│
├── IMPLEMENTATION_SUMMARY.md ...................... 📄 [NEW] This document
├── BATCH_EXECUTION_GUIDE.md ....................... 📄 [NEW] Quick start
├── RANDOM_USER_BATCH_README.md .................... 📄 [NEW] Full documentation
└── ARCHITECTURE_DETAILS.md ........................ 📄 [NEW] Technical details

```

## 🔄 Batch Execution Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│  STEP 1: BATCH START                                            │
│  ─────────────────────────────────────────────────────────────  │
│  User Initiates Batch Execution                                 │
│  • Execute Anonymous: RandomUserBatchUtil.executeBatch()       │
│  • Scheduled Job: Via Schedulable class                        │
│  • Flow/Button: Via execute() method call                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 2: START METHOD                                           │
│  ─────────────────────────────────────────────────────────────  │
│  Fetch Data from Random User API                               │
│                                                                  │
│  HttpRequest req = new HttpRequest();                          │
│  req.setEndpoint('https://randomuser.me/api?results=10');     │
│  req.setMethod('GET');                                         │
│                                                                  │
│  HttpResponse res = http.send(req);  ◄─── API CALLOUT         │
│                                                                  │
│  Parse JSON Response                                            │
│  ✓ Validate HTTP 200 status                                    │
│  ✓ Log to API_Log__c                                           │
│  ✓ Extract results array                                       │
│  ✓ Return List<Object>                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 3: EXECUTE METHOD (processes scope of records)           │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  For each user in scope {                                      │
│    Extract:                                                     │
│    • name.first & name.last                                    │
│    • email, phone, cell                                        │
│    • location (street, city, state, country, postcode)        │
│                                                                  │
│    Create Contact Record ◄────── DML #1                        │
│    • Set FirstName, LastName                                   │
│    • Set Email, Phone, MobilePhone                             │
│    • Set MailingStreet, MailingCity, etc.                     │
│                                                                  │
│    Create Account Record ◄────── DML #1 (same)                 │
│    • Name = FirstName + LastName + " Household"                │
│    • Set BillingStreet, BillingCity, etc.                     │
│  }                                                              │
│                                                                  │
│  Insert Accounts (Database.insert(list, false))               │
│  ◄────────────────────────────────── DML #2 (actual insert)   │
│                                                                  │
│  Query Created Accounts                                        │
│  ◄────────────────────────────────── SOQL #1                  │
│                                                                  │
│  Link Contacts to Accounts                                     │
│  • Map account names to IDs                                    │
│  • Set Contact.AccountId                                       │
│                                                                  │
│  Insert Contacts (Database.insert(list, false))               │
│  ◄────────────────────────────────── DML #3 (actual insert)   │
│                                                                  │
│  Log Any Exceptions                                            │
│  ✓ If records fail, log to Exception_Log__c                  │
│  ✓ Continue processing other records                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 4: FINISH METHOD                                          │
│  ─────────────────────────────────────────────────────────────  │
│  Finalize Batch Execution                                       │
│                                                                  │
│  • Log completion timestamp                                     │
│  • Record batch job ID                                          │
│  • Perform cleanup (if needed)                                 │
│  • Trigger notifications (optional)                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ✅ BATCH COMPLETE
                        ~30 seconds
                
        Results:
        • 10 Contacts created
        • 10 Accounts created
        • 10 Relationships established
        • All data logged
```

## 📡 API Response Processing

```
API CALL: GET https://randomuser.me/api?results=10

RESPONSE:
{
  "results": [
    {
      "name": { "first": "Kavyashri", "last": "Shroff" },
      "email": "kavyashri.shroff@example.com",
      "phone": "7182654354",
      "cell": "8795439569",
      "location": {
        "street": { "number": 8465, "name": "Tripolia Bazar" },
        "city": "Farrukhabad",
        "state": "Madhya Pradesh",
        "country": "India",
        "postcode": 70514
      }
    },
    ... (9 more records)
  ],
  "info": { "seed": "...", "results": 10, "page": 1, "version": "1.4" }
}

PARSING ▼

SALESFORCE RECORDS CREATED:

Contact {
  FirstName: "Kavyashri"
  LastName: "Shroff"
  Email: "kavyashri.shroff@example.com"
  Phone: "7182654354"
  MobilePhone: "8795439569"
  MailingStreet: "8465 Tripolia Bazar"
  MailingCity: "Farrukhabad"
  MailingState: "Madhya Pradesh"
  MailingCountry: "India"
  MailingPostalCode: "70514"
  AccountId: (linked to Account)
}

Account {
  Name: "Kavyashri Shroff Household"
  BillingStreet: "8465 Tripolia Bazar"
  BillingCity: "Farrukhabad"
  BillingState: "Madhya Pradesh"
  BillingCountry: "India"
  BillingPostalCode: "70514"
  Phone: "7182654354"
}
```

## 🧠 Class Relationships

```
RandomUserBatch (Main)
│
├─► Extends: nothing (implements interfaces)
├─► Implements: Database.Batchable<Object>
├─► Implements: Database.AllowsCallouts
│
├─► Uses: APILogger
│   └─► Logs: API_Log__c
│
├─► Uses: ExceptionLogger
│   └─► Logs: Exception_Log__c
│
├─► Creates: Contact (Salesforce object)
└─► Creates: Account (Salesforce object)


RandomUserBatchUtil (Helper)
│
├─► Calls: RandomUserBatch.executeBatch()
│
└─► Provides: Easy execution methods
    └─► executeBatch()
    └─► executeBatch(Integer batchSize)


RandomUserBatchTest (Testing)
│
├─► Tests: RandomUserBatch
│
├─► Uses: MockHttpResponse
│   └─► Implements: HttpCalloutMock
│
└─► Verifies:
    ├─► Contact creation
    ├─► Account creation
    └─► Contact-Account relationships
```

## 🎯 Execution Paths

### Path 1: Manual One-Time Execution
```
Developer/Admin
     │
     ▼
Execute Anonymous
     │
     ├─ RandomUserBatchUtil.executeBatch()
     │
     ▼
Salesforce Batch Engine
     │
     ▼
RandomUserBatch (Batchable)
     │
     ├─ start()  → API Call → 10 users fetched
     ├─ execute() → Create 10 Contacts + 10 Accounts
     └─ finish() → Log completion
     │
     ▼
Database (Salesforce)
     ├─ 10 Contact records inserted
     └─ 10 Account records inserted
```

### Path 2: Scheduled Daily Execution
```
Scheduled Time (2 AM Daily)
     │
     ▼
CronTrigger fires RandomUserBatchSchedulable
     │
     ▼
RandomUserBatchSchedulable.execute()
     │
     ├─ RandomUserBatchUtil.executeBatch()
     │
     ▼
[Same as Path 1]
     │
     ▼
10 new Contact/Account pairs every day
(3,650 pairs per year)
```

### Path 3: Flow/Process Execution
```
Flow or Process
     │
     ├─ Call Apex Action
     │
     ▼
RandomUserBatchUtil.executeBatch()
     │
     ▼
[Same as Path 1]
```

## 📊 Data Volume Scenarios

### Scenario 1: Single Execution
```
Batch Size: 10
Records Processed: 10
Execution Time: ~30 seconds
Results:
  ✓ 10 Contacts
  ✓ 10 Accounts
  ✓ 1 API call
  ✓ 2 DML operations
```

### Scenario 2: Daily Execution (1 month)
```
Batch Size: 10
Frequency: Daily (30 days)
Total Records: 300
Total API Calls: 30
Results:
  ✓ 300 Contacts
  ✓ 300 Accounts
  ✓ 30 API calls
  ✓ 60 DML operations
```

### Scenario 3: Daily Execution (1 year)
```
Batch Size: 10
Frequency: Daily (365 days)
Total Records: 3,650
Total API Calls: 365
Results:
  ✓ 3,650 Contacts
  ✓ 3,650 Accounts
  ✓ 365 API calls
  ✓ 730 DML operations
```

## 🔐 Security & Limits

### Governor Limits (per batch)
```
┌─────────────────────┬───────┬────────┬────────┐
│ Limit               │ Used  │ Limit  │ Status │
├─────────────────────┼───────┼────────┼────────┤
│ API Callouts        │ 1     │ 100    │ ✅    │
│ DML Statements      │ 3     │ 150    │ ✅    │
│ SOQL Queries        │ 1     │ 100    │ ✅    │
│ Heap Size           │ ~2MB  │ 6MB    │ ✅    │
│ Execution Time      │ ~30s  │ ∞      │ ✅    │
└─────────────────────┴───────┴────────┴────────┘
```

### Data Privacy
```
API Response (Random User API)
        │
        ├─ Full JSON logged to API_Log__c
        │  (for debugging/auditing)
        │
        ├─ Parsed data used to create records
        │
        └─ Exceptions logged to Exception_Log__c
           (with context for troubleshooting)

No PII stored beyond what's needed for:
• Record creation
• Error troubleshooting
• Audit compliance
```

## 🚨 Error Handling Flow

```
EXECUTION
    │
    ├─ API Callout Error
    │  └─ Log to API_Log__c
    │  └─ Throw CalloutException
    │  └─ ❌ Batch aborts (no records created)
    │
    ├─ User Processing Error
    │  └─ Log to Exception_Log__c
    │  └─ ✅ Continue to next user
    │
    ├─ Account Insert Error
    │  └─ Log to Exception_Log__c
    │  └─ ✅ Continue with Contacts
    │
    └─ Contact Insert Error
       └─ Log to Exception_Log__c
       └─ ✅ Continue to next Contact
```

## 📋 Quick Command Reference

### Execute Batch
```apex
Id jobId = RandomUserBatchUtil.executeBatch();
```

### Check Results
```apex
SELECT COUNT() FROM Contact WHERE Email LIKE '%.com';
SELECT COUNT() FROM Account WHERE Name LIKE '%Household';
```

### View Logs
```apex
SELECT * FROM API_Log__c ORDER BY CreatedDate DESC LIMIT 20;
SELECT * FROM Exception_Log__c ORDER BY CreatedDate DESC LIMIT 20;
```

### Monitor Batch
```apex
SELECT Status, JobItemsProcessed FROM AsyncApexJob WHERE JobType = 'BatchApex';
```

### Schedule Batch
```apex
System.schedule('Batch Name', '0 0 2 * * ?', new RandomUserBatchSchedulable());
```

---

**Version:** 1.0
**Last Updated:** November 14, 2025
