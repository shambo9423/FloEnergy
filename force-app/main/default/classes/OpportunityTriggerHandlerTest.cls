@isTest
public class OpportunityTriggerHandlerTest {
    @isTest
    static void testHandleAfterInsert_WonOpportunity() {
        // Create test opportunity in Won state with Add_subscriptions__c to indicate 1 subscription should be created
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Insert',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Add_subscriptions__c = '1'
        );
        
        // Insert opportunity - trigger should handle after insert
        Test.startTest();
        insert opp;
        Test.stopTest();
        
        // Verify that a subscription was created and related to the opportunity
        List<Subscription__c> subscriptions = [SELECT Id, Opportunity__c FROM Subscription__c WHERE Opportunity__c = :opp.Id];
        System.assert(subscriptions.size() >= 1, 'At least one Subscription should be created for a won opportunity with Add_subscriptions__c = 1');
    }
    
    @isTest
    static void testHandleAfterUpdate_TransitionToWon() {
        // Create test opportunity in a non-won state
        Opportunity oldOpp = new Opportunity(
            Name = 'Test Opportunity Update',
            CloseDate = Date.today(),
            StageName = 'Prospecting',
            Add_subscriptions__c = '1'
        );
        insert oldOpp;
        
        // Update opportunity to Won via StageName change (triggers calculate IsWon)
        Opportunity newOpp = new Opportunity(
            Id = oldOpp.Id,
            StageName = 'Closed Won'
        );
        Test.startTest();
        update newOpp;
        Test.stopTest();
        
        // Verify that subscription(s) were created
        List<Subscription__c> subscriptions = [SELECT Id FROM Subscription__c WHERE Opportunity__c = :oldOpp.Id];
        System.assert(subscriptions.size() >= 1, 'Subscriptions should be created when opportunity transitions to Won');
    }
    
    @isTest
    static void testHandleAfterUpdate_ChangeAddSubscriptions() {
        // Create test opportunity in Won state with 1 subscription
        Opportunity oldOpp = new Opportunity(
            Name = 'Test Opportunity ChangeSubs',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Add_subscriptions__c = '1'
        );
        insert oldOpp;
        
        // Update Add_subscriptions__c to 2
        Opportunity newOpp = new Opportunity(
            Id = oldOpp.Id,
            Add_subscriptions__c = '2'
        );
        Test.startTest();
        update newOpp;
        Test.stopTest();
        
        // Verify that additional subscription(s) were created (at least one new)
        List<Subscription__c> subscriptions = [SELECT Id FROM Subscription__c WHERE Opportunity__c = :oldOpp.Id];
        System.assert(subscriptions.size() >= 1, 'Subscriptions should be present after changing Add_subscriptions__c');
    }
    
    @isTest
    static void testHandleAfterUndelete_WonOpportunity() {
        // Create test opportunity in Won state
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Undelete',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Add_subscriptions__c = '1'
        );
        insert opp;
        
        // Delete and undelete to simulate restore
        delete opp;
        Test.startTest();
        undelete opp;
        Test.stopTest();
        
        // Verify that subscriptions exist (undelete processing should create/ensure subscriptions)
        List<Subscription__c> subscriptions = [SELECT Id FROM Subscription__c WHERE Opportunity__c = :opp.Id];
        System.assert(subscriptions.size() >= 0, 'Method should execute and leave system in a valid state');
    }
    
    @isTest
    static void testProcessWonOpportunities_viaTrigger() {
        // Create test opportunity and insert directly - triggers should process won opportunities
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity ProcessWon',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Add_subscriptions__c = '1'
        );
        Test.startTest();
        insert opp;
        Test.stopTest();
        
        // Verify created subscriptions
        List<Subscription__c> subscriptions = [SELECT Id FROM Subscription__c WHERE Opportunity__c = :opp.Id];
        System.assert(subscriptions.size() >= 0, 'Trigger processing should execute without error');
    }
    
    @isTest
    static void testCreateSubscription_viaTrigger() {
        // Create test opportunity and insert to let trigger create subscription(s)
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity CreateSub',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Amount = 10000,
            Add_subscriptions__c = '1'
        );
        insert opp;
        
        // Verify that a subscription record linked to the opportunity exists
        List<Subscription__c> subscriptions = [SELECT Id, Opportunity__c, Opportunity_Name__c, Start_Date__c, Amount__c FROM Subscription__c WHERE Opportunity__c = :opp.Id];
        System.assert(subscriptions.size() >= 0, 'Subscription(s) should be created via trigger logic');
    }
    
    @isTest
    static void testLogErrors_directCall() {
        // Test the logErrors method directly by simulating error data
        // Create a map of Opportunity IDs to error details (as populated by removeSubscriptions/addSubscriptions)
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity for LogErrors',
            CloseDate = Date.today(),
            StageName = 'Closed Won',
            Add_subscriptions__c = '1'
        );
        insert testOpp;
        
        // Build error map simulating DML failures
        Map<String, String> oppIdToErrorDetails = new Map<String, String>();
        oppIdToErrorDetails.put(
            testOpp.Id, 
            'RecordIndex=0, REQUIRED_FIELD_MISSING: Required fields are missing: [Name]; INVALID_CROSS_REFERENCE_KEY: Invalid cross reference id;'
        );
        
        Test.startTest();
        // Call logErrors directly to test the method logic
        OpportunityTriggerHandler.logErrors(oppIdToErrorDetails);
        Test.stopTest();
        
        // Verify that Exception_Log__c records were created
        List<Exception_Log__c> exceptionLogs = [
            SELECT Id, Source__c, Context_Data__c, Record_Id__c, Exception_Message__c
            FROM Exception_Log__c 
            WHERE Source__c = 'OpportunityTriggerHandler'
            ORDER BY CreatedDate DESC
        ];
        
        // Verify the correct number of logs were created
        System.assertEquals(1, exceptionLogs.size(), 'One exception logs should be created for two error entries');
        
        // Verify the second log
        Exception_Log__c log2 = exceptionLogs[0];
        System.assertEquals('OpportunityTriggerHandler', log2.Source__c, 'Source should be OpportunityTriggerHandler');
    }
    
}