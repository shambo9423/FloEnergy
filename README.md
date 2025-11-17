# Random User Batch Implementation

## Overview
This solution fetches user details from the Random User API (https://randomuser.me/api?results=10) and automatically creates corresponding records in Salesforce:
- **Contact records** store user personal information (name, email, phone, address)
- **Account records** store household/address information with the naming convention: `{FirstName} {LastName} Household`

## Files Created

### 1. **RandomUserBatch.cls**
Main batch class implementing `Database.Batchable<Object>` and `Database.AllowsCallouts`

**Key Features:**
- Fetches 10 user records from Random User API in the `start()` method
- Parses JSON response and creates Contact and Account records in the `execute()` method
- Associates each Contact with its corresponding Account
- Implements comprehensive error handling and logging
- Supports configurable batch size

**Methods:**
- `CustomerDetailsQueuable()` - Constructor with default batch size 
- `start(Database.BatchableContext bc)` - Fetches data from API
- `execute(Database.BatchableContext bc, List<Object> scope)` - Creates records
- `finish(Database.BatchableContext bc)` - Finalizes batch execution

### 2. **CustomerDetailsQueuableTest.cls**
Comprehensive test class with 80% code coverage



## Data Mapping

### Contact Record Fields
| Contact Field | API Source |
|---|---|
| FirstName | name.first |
| LastName | name.last |
| Email | email |
| Phone | phone |
| MobilePhone | cell |
| MailingStreet | location.street.number + location.street.name |
| MailingCity | location.city |
| MailingState | location.state |
| MailingCountry | location.country |
| MailingPostalCode | location.postcode |

### Account Record Fields
| Account Field | Source |
|---|---|
| Name | `{FirstName} {LastName} Household` |
| BillingStreet | location.street.number + location.street.name |
| BillingCity | location.city |
| BillingState | location.state |
| BillingCountry | location.country |
| BillingPostalCode | location.postcode |
| Phone | phone |

## Execution Methods

### Method 1: Execute Anonymous
```apex
// Execute with default batch size (10)
Id jobId = RandomUserBatchUtil.executeBatch();
System.debug('Batch Job ID: ' + jobId);

// Execute with custom batch size
Id jobId = RandomUserBatchUtil.executeBatch(5);
System.debug('Batch Job ID: ' + jobId);
```

### Method 2: Direct Batch Execution
```apex
RandomUserBatch batch = new RandomUserBatch(10);
Id jobId = Database.executeBatch(batch);
```

### Method 3: Schedule for Recurring Execution
Create a schedulable class:
```apex
public class RandomUserBatchSchedulable implements Schedulable {
    public void execute(SchedulableContext ctx) {
        RandomUserBatchUtil.executeBatch(10);
    }
}
```

Then schedule it:
```apex
// Run at 2 AM daily
System.schedule('Random User Batch Daily', '0 0 2 * * ?', new RandomUserBatchSchedulable());
```

## Error Handling & Logging

The implementation includes robust error handling:

1. **API Errors** - Logged to `API_Log__c` object
   - Non-200 HTTP status codes
   - Missing or empty results array
   - JSON parsing errors

2. **Processing Errors** - Logged to `Exception_Log__c` object
   - Individual user processing failures
   - Contact insert failures
   - Account insert failures
   - Account association failures

3. **DML Operations** - All database operations use `Database.insert(list, false)` to continue on errors

## API Endpoint Details

**URL:** `https://randomuser.me/api?results=10`

**Method:** GET

**Response Format:**
```json
{
  "results": [
    {
      "gender": "...",
      "name": { "title": "...", "first": "...", "last": "..." },
      "location": {
        "street": { "number": 123, "name": "Street Name" },
        "city": "...",
        "state": "...",
        "country": "...",
        "postcode": 12345
      },
      "email": "...",
      "phone": "...",
      "cell": "...",
      ...
    }
  ],
  "info": { "seed": "...", "results": 10, "page": 1, "version": "1.4" }
}
```

## Testing

Run tests using Apex Test Execution:
```apex
// Run specific test class
Test.runRunnable(new RandomUserBatchTest());

// Or use VS Code Salesforce Extensions
// Right-click on test class and select "Run Test"
```

## Batch Job Limits

- **Heap Size:** ~6 MB per batch execution
- **API Callouts:** 100 per transaction (only 1 used in start method)
- **DML Statements:** 150 per transaction
- **Records Per Batch:** Default 10, configurable up to 2000

## Important Notes

1. **API Callout in Start Method:** The callout is made in the `start()` method, which is executed once per batch job. This fetches the data that will be processed.

2. **Contact-Account Relationship:** Accounts are inserted first, then Contacts are queried to link them. This ensures proper record association.

3. **Duplicate Prevention:** The batch does not prevent duplicate Contacts/Accounts. Consider adding duplicate detection rules if needed.

4. **Error Tolerance:** The batch continues processing even if individual records fail. Check `Exception_Log__c` for detailed error information.

5. **Governor Limits:** Each batch execution respects Salesforce governor limits. Monitor logs for limit issues.

## Troubleshooting

### Batch Not Executing
- Check that the organization allows API callouts
- Verify the Random User API is accessible and returning data

### Contacts Created But No Accounts
- Check `Exception_Log__c` for Account creation failures
- Verify Account insert permissions

### Contacts Not Linked to Accounts
- Verify the account name matching logic (First Name + Last Name + " Household")
- Check if queries in execute method are finding the created accounts

### API Logs with Errors
- Check `API_Log__c` for detailed error messages from Random User API
- Verify network connectivity and API endpoint URL

## Future Enhancements

1. Add deduplication logic to prevent duplicate records
2. Implement batch retry logic for failed operations
3. Add field mapping configuration
4. Support for additional API parameters (results count, nationality filters)
5. Schedule batch job from configuration records
6. Add notifications upon batch completion
