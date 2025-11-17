// ========================================
// RANDOM USER BATCH EXECUTION EXAMPLES
// ========================================
// Copy and paste any of these into Execute Anonymous in VS Code
// ========================================

// EXAMPLE 1: Execute with default batch size (10)
Id jobId = RandomUserBatchUtil.executeBatch();
System.debug('Batch Job ID: ' + jobId);

// EXAMPLE 2: Execute with custom batch size (5)
// Id jobId = RandomUserBatchUtil.executeBatch(5);
// System.debug('Batch Job ID: ' + jobId);

// EXAMPLE 3: Direct batch execution with default constructor
// RandomUserBatch batch = new RandomUserBatch();
// Id jobId = Database.executeBatch(batch);
// System.debug('Batch Job ID: ' + jobId);

// EXAMPLE 4: Direct batch execution with custom batch size
// RandomUserBatch batch = new RandomUserBatch(10);
// Id jobId = Database.executeBatch(batch, 10);
// System.debug('Batch Job ID: ' + jobId);

// ========================================
// VERIFICATION QUERIES
// ========================================
// Run these after the batch completes to verify data creation

// View created contacts
// SELECT Id, FirstName, LastName, Email, Phone FROM Contact ORDER BY CreatedDate DESC LIMIT 20

// View created accounts with Household suffix
// SELECT Id, Name, BillingCity, BillingCountry FROM Account WHERE Name LIKE '%Household' ORDER BY CreatedDate DESC LIMIT 20

// View contact to account relationships
// SELECT Id, FirstName, LastName, Account.Name, Email FROM Contact WHERE AccountId != null ORDER BY CreatedDate DESC LIMIT 20

// View API logs
// SELECT Id, API_Endpoint__c, Status__c, Error_Message__c FROM API_Log__c ORDER BY Timestamp__c DESC LIMIT 20

// View exception logs (if any errors occurred)
// SELECT Id, Source__c, Exception_Type__c, Exception_Message__c FROM Exception_Log__c ORDER BY Timestamp__c DESC LIMIT 20

// ========================================
// MONITORING BATCH EXECUTION
// ========================================

// View batch job status
// SELECT Id, ApexClass.Name, Status, JobItemsProcessed, TotalJobItems FROM AsyncApexJob WHERE JobType = 'BatchApex' ORDER BY CreatedDate DESC LIMIT 10

// ========================================
// SCHEDULING FOR RECURRING EXECUTION
// ========================================

// Create schedulable class first, then use this:
// System.schedule('Random User Batch - Daily 2AM', '0 0 2 * * ?', new RandomUserBatchSchedulable());

// To view scheduled jobs:
// SELECT Id, CronJobDetail.Name, State, NextFireTime FROM CronTrigger WHERE CronJobDetail.JobType = 'BatchApex' ORDER BY NextFireTime

// ========================================
// CANCELING A BATCH JOB
// ========================================

// AsyncApexJob job = [SELECT Id FROM AsyncApexJob WHERE JobType = 'BatchApex' AND Status = 'Queued' ORDER BY CreatedDate DESC LIMIT 1];
// System.abortJob(job.Id);

// ========================================
// EXAMPLE: Creating a Schedulable Class
// ========================================
/*
public class RandomUserBatchSchedulable implements Schedulable {
    public void execute(SchedulableContext ctx) {
        RandomUserBatchUtil.executeBatch(10);
    }
}

// Then schedule it from Execute Anonymous:
System.schedule('Random User Batch - Daily 2AM', '0 0 2 * * ?', new RandomUserBatchSchedulable());

// Cron expression format: (seconds minutes hours day month day_of_week)
// Examples:
// '0 0 2 * * ?' - Every day at 2:00 AM
// '0 0 2 ? * MON' - Every Monday at 2:00 AM
// '0 0 */2 * * ?' - Every 2 hours
// '0 0 2 1 * ?' - First day of every month at 2:00 AM
*/

// ========================================
// CLEANUP (if needed)
// ========================================

// Delete all created contacts
// DELETE [SELECT Id FROM Contact WHERE Email LIKE '%.com'];

// Delete all household accounts
// DELETE [SELECT Id FROM Account WHERE Name LIKE '%Household'];

// Delete all API logs
// DELETE [SELECT Id FROM API_Log__c];

// Delete all exception logs
// DELETE [SELECT Id FROM Exception_Log__c];
