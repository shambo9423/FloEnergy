# Get User Details Integration (Queueable)

## Overview
This repository implements an asynchronous integration that fetches user details from a Random User-style API and creates corresponding Salesforce records (Account + Contact). The actual implementation uses a Queueable (`CustomerDetailsQueuable`) rather than a Batchable class. The controller and tests live under `force-app/main/default/classes` and the LWC table controller is in `force-app/main/default/lwc`.

Key behaviors:
- Fetches user JSON from an API endpoint configured in custom metadata (`UserDetailsAPI_Config__mdt`)
- Maps API payload to Contact and Account SObjects
- Inserts Accounts first (partial success DML), then Contacts and maps AccountId using insert SaveResults
- Logs API call details to `API_Log__c` and exceptions to `Exception_Log__c`

## Important files

- `force-app/main/default/classes/CustomerDetailsQueuable.cls` — Queueable implementation that performs the callout, parses payload, and creates Account + Contact records.
- `force-app/main/default/classes/CustomerDetailsQueuableTest.cls` — Apex tests for the queueable (mocks callouts and asserts record creation).
- `force-app/main/default/classes/ExceptionLogger.cls` and `ExceptionLoggerTest.cls` — Utilities and tests for logging exceptions to `Exception_Log__c`.
- `force-app/main/default/classes/APILogger.cls` and `APILoggerTest.cls` — Logs API callouts to `API_Log__c`.
- `force-app/main/default/classes/SubscriptionController.cls` — Apex controller used by an LWC datatable (`subscriptionTable`), including helper functions and comments.
- `force-app/main/default/lwc/subscriptionTable/` — Lightning Web Component used by the UI (columns, pagination, pageInfo fix for zero rows).
- `scripts/apex/randomuser_batch_execution.apex` — Example Execute Anonymous scripts to run and verify the integration.

## Execution

This integration is implemented as a Queueable. Use Execute Anonymous or an Apex schedulable to run it.

Example: enqueue the Queueable
```apex
// Simple enqueue
System.enqueueJob(new CustomerDetailsQueuable());

// In tests (use Test.setMock for callouts):
Test.startTest();
System.enqueueJob(new CustomerDetailsQueuable());
Test.stopTest();
```

If you prefer a scheduled job, create a small Schedulable class that enqueues the job and schedule it via `System.schedule`.

## Configuration

- Custom metadata `UserDetailsAPI_Config__mdt` (DeveloperName = `GetUserDetailsAPI`) must be present in the org. It contains the API endpoint, HTTP method, and timeout used by the Queueable.
- Table configuration metadata `TableConfig__mdt` drives the `SubscriptionController` behavior in the LWC.


Or run individual tests from the Salesforce Extensions for VS Code: right-click a test class and select "Run Test".

Note: Some tests rely on custom metadata being present in the target org. If tests fail due to missing metadata, deploy the corresponding `force-app/main/default/customMetadata` files first.

## Troubleshooting

- Contacts or Accounts not created: Inspect `Exception_Log__c` and `API_Log__c` records via SOQL.
- Callouts failing: Ensure the API endpoint configured in `UserDetailsAPI_Config__mdt` is reachable from the org and that Named Credentials / CSP settings allow the callout.
- Tests failing due to validation rules: Update test data to satisfy org-specific validation rules (phone format, required fields), or adapt tests accordingly.

## Notes & Future Work

- The code uses partial-success DML (`Database.insert(list, false)`) to tolerate individual record failures and log them for inspection.
- Consider adding deduplication, configurable field mappings, and a robust retry mechanism for transient API failures.


## Demo

https://www.loom.com/share/bd3e64f089be4765bb7ffeca31975a81