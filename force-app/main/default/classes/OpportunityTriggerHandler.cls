/**
* @description       : Handles creation of Subscription records when Opportunity reaches Won status
*                      Manages the full lifecycle of subscriptions: creation, deletion, and error logging
*                      via partial-success DML operations.
* @author            : shambo.ray@gmail.com
* @group             : Opportunity Management
* @last modified on  : 11-15-2025
* @notes             :
*  - Uses Database.insert/delete with AllowPartialSuccess (allOrNone=false) to handle errors gracefully
*  - Aggregates DML errors per opportunity and persists them to Exception_Log__c for observability
*  - Handles three trigger contexts: after insert, after update (with state change detection), after undelete
*  - Subscription naming follows format SUB01, SUB02, etc., based on Add_subscriptions__c picklist value
**/
public with sharing class OpportunityTriggerHandler {
    /**
     * Handle after insert: create subscriptions for Opportunities inserted directly as Won
     * 
     * Filters the incoming opportunities for those with IsWon = true (i.e., StageName = 'Closed Won')
     * and delegates to central processing logic.
     * 
     * @param newOpps List of newly inserted Opportunity records from trigger context
     */
    public static void handleAfterInsert(List<Opportunity> newOpps) {
        List<Opportunity> wonOpps = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            if (opp.IsWon) {
                wonOpps.add(opp);
            }
        }
        if (!wonOpps.isEmpty()) {
            processWonOpportunities(wonOpps);
        }
    }

    /**
     * Handle after update: create subscriptions for Opportunities that are Won
     * 
     * Detects two distinct scenarios and processes only relevant opportunities:
     * - Transition: Opportunity's IsWon status changed from false to true (new Won state)
     * - Update: Opportunity is already Won but Add_subscriptions__c field value changed
     * 
     * Prevents unnecessary processing of non-Won opportunities or Won opportunities 
     * where the subscription count has not changed.
     * 
     * @param newOpps List of updated Opportunity records from trigger context (new values)
     * @param oldMap Map of Opportunity IDs to their pre-update values for comparison
     */
    public static void handleAfterUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        List<Opportunity> wonOpps = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            
            // Case 1: Opportunity transitioned to Won status
            if (opp.IsWon && !oldOpp.IsWon) {
                wonOpps.add(opp);
            }
            // Case 2: Opportunity is already Won and Add_subscriptions__c changed
            else if (opp.IsWon && oldOpp.IsWon && opp.Add_subscriptions__c != oldOpp.Add_subscriptions__c) {
                wonOpps.add(opp);
            }
        }
        if (!wonOpps.isEmpty()) {
            processWonOpportunities(wonOpps);
        }
    }

    /**
     * Handle after undelete: create subscriptions for restored Opportunities that are Won
     * 
     * Restores subscription records for any undeleted opportunities that are in Won state.
     * This ensures data consistency when opportunities are restored from recycle bin.
     * 
     * @param newOpps List of undeleted Opportunity records from trigger context
     */
    public static void handleAfterUndelete(List<Opportunity> newOpps) {
        List<Opportunity> wonOpps = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            if (opp.IsWon) {
                wonOpps.add(opp);
            }
        }
        if (!wonOpps.isEmpty()) {
            processWonOpportunities(wonOpps);
        }
    }

    /**
     * Centralized logic to process Won Opportunities and manage subscriptions
     * 
     * Workflow:
     * 1. Builds map of Opportunity IDs → subscription count from Add_subscriptions__c picklist
     * 2. Generates new Subscription__c records in memory (SUB01, SUB02, ... format)
     * 3. Queries for existing subscriptions linked to these opportunities and marks for deletion
     * 4. Executes removal of old subscriptions with partial-success DML (AllowPartialSuccess=false)
     * 5. Executes insertion of new subscriptions with partial-success DML (AllowPartialSuccess=false)
     * 6. Aggregates any DML errors by Opportunity ID and persists them to Exception_Log__c
     * 
     * This approach ensures subscriptions are regenerated cleanly when the subscription count changes,
     * and any DML failures are captured for operational debugging.
     * 
     * @param wonOpps List of Won Opportunity records requiring subscription processing
     */
    private static void processWonOpportunities(List<Opportunity> wonOpps) {
        List<Subscription__c> toInsert = new List<Subscription__c>();
        List<Subscription__c> toRemove = new List<Subscription__c>();
        Map<Id, Integer> oppToSubCount = new Map<Id, Integer>();
        Map<String, String> oppIdToErrorDetails = new Map<String, String>();

        // Build map of Opportunity IDs to subscription count from the Add_subscriptions__c picklist
        for (Opportunity opp : wonOpps) {
            String pickVal = opp.Add_subscriptions__c;
            if (String.isBlank(pickVal)) continue;
            Integer num = Integer.valueOf(pickVal);
            oppToSubCount.put(opp.Id, num);
            
            // Create subscription records with SUB01, SUB02, etc. format
            for (Integer i = 1; i <= num; i++) {
                toInsert.add(createSubscription(opp, i));
            }
        }

        // Query for existing subscriptions on these opportunities (to remove them first)
        if (!oppToSubCount.isEmpty()) {
            for (Subscription__c sub : [SELECT Id, Opportunity__c FROM Subscription__c 
                                         WHERE Opportunity__c IN :oppToSubCount.keySet()]) {
                toRemove.add(sub);
            }
        }

        // Remove existing subscriptions
        if (!toRemove.isEmpty()) {
            removeSubscriptions(toRemove, oppIdToErrorDetails);
        }

        // Insert new subscriptions
        if (!toInsert.isEmpty()) {
            addSubscriptions(toInsert, oppIdToErrorDetails);
        }

        // Log errors if any occurred
        if (!oppIdToErrorDetails.isEmpty()) {
            logErrors(oppIdToErrorDetails);
        }
    }

    /**
     * Removes existing subscriptions associated with target opportunities
     * 
     * Executes Database.delete with AllowPartialSuccess (allOrNone=false) to allow some records
     * to delete successfully while capturing errors for failed deletions.
     * 
     * Iterates through DeleteResult[] to identify failures and aggregates error details
     * (status code, message) per Opportunity ID into oppIdToErrorDetails map.
     * Multiple errors for the same opportunity are concatenated with pipe separators.
     * 
     * @param toRemove List of Subscription__c records to delete
     * @param oppIdToErrorDetails Map to aggregate errors by Opportunity ID (mutated by this method)
     */
    private static void removeSubscriptions(List<Subscription__c> toRemove, Map<String, String> oppIdToErrorDetails) {
        // Use Database.delete with AllowPartialSuccess to capture individual record errors
        Database.DeleteResult[] deleteResults = Database.delete(toRemove, false);

        for (Integer i = 0; i < deleteResults.size(); i++) {
            Database.DeleteResult sr = deleteResults[i];
            if (!sr.isSuccess()) {
                String oppId = toRemove[i].Opportunity__c;
                String recordErrors = '';
                for (Database.Error err : sr.getErrors()) {
                    recordErrors += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                // Append errors for this Opportunity ID
                if (oppIdToErrorDetails.containsKey(oppId)) {
                    oppIdToErrorDetails.put(oppId, oppIdToErrorDetails.get(oppId) + ' | RecordIndex=' + i + ', ' + recordErrors);
                } else {
                    oppIdToErrorDetails.put(oppId, 'RecordIndex=' + i + ', ' + recordErrors);
                }
            }
        }
    }

    /**
     * Inserts new subscription records associated with target opportunities
     * 
     * Executes Database.insert with AllowPartialSuccess (allOrNone=false) to allow some records
     * to insert successfully while capturing errors for failed insertions.
     * 
     * Iterates through SaveResult[] to identify failures and aggregates error details
     * (status code, message) per Opportunity ID into oppIdToErrorDetails map.
     * Multiple errors for the same opportunity are concatenated with pipe separators.
     * 
     * @param toInsert List of Subscription__c records to insert
     * @param oppIdToErrorDetails Map to aggregate errors by Opportunity ID (mutated by this method)
     */
    private static void addSubscriptions(List<Subscription__c> toInsert, Map<String, String> oppIdToErrorDetails) {
        // Use Database.insert with AllowPartialSuccess to capture individual record errors
        Database.SaveResult[] saveResults = Database.insert(toInsert, false);

        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            if (!sr.isSuccess()) {
                String oppId = toInsert[i].Opportunity__c;
                String recordErrors = '';
                for (Database.Error err : sr.getErrors()) {
                    recordErrors += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                // Append errors for this Opportunity ID
                if (oppIdToErrorDetails.containsKey(oppId)) {
                    oppIdToErrorDetails.put(oppId, oppIdToErrorDetails.get(oppId) + ' | RecordIndex=' + i + ', ' + recordErrors);
                } else {
                    oppIdToErrorDetails.put(oppId, 'RecordIndex=' + i + ', ' + recordErrors);
                }
            }
        }
    }

    /**
     * Factory method to create a single Subscription__c record from an Opportunity
     * 
     * Generates a subscription with:
     * - Name: Sequential format SUB01, SUB02, ..., SUB09, SUB10, etc.
     * - Opportunity reference and name (denormalized for UI performance)
     * - Start date: Opportunity close date
     * - End date: Close date + 12 months (1-year term)
     * - Amount: Inherited from the Opportunity
     * 
     * @param opp Source Opportunity record
     * @param n Sequence number (1-based) used to generate subscription name
     * @return Subscription__c instance (not yet inserted)
     */
    private static Subscription__c createSubscription(Opportunity opp, Integer n) {
        Subscription__c s = new Subscription__c();
        // Format subscription name as SUB01, SUB02, ... SUB20
        s.Name = 'SUB' + (n < 10 ? '0' : '') + String.valueOf(n);
        s.Opportunity__c = opp.Id;
        s.Opportunity_Name__c = opp.Name; // Kept as regular field for performance
        s.Start_Date__c = opp.CloseDate;
        s.End_Date__c = opp.CloseDate.addMonths(12);
        s.Amount__c = opp.Amount;
        return s;
    }

    /**
     * Persists aggregated DML error details to Exception_Log__c for observability
     * 
     * Iterates through oppIdToErrorDetails map (populated by removeSubscriptions and addSubscriptions)
     * and creates one Exception_Log__c record per Opportunity ID with accumulated error messages.
     * 
     * Uses ExceptionLogger utility to create and populate Exception_Log__c instances with:
     * - Source: 'OpportunityTriggerHandler' (for log filtering)
     * - Exception: Generic DmlException with description
     * - Context: Aggregated error details (status codes, messages, record indices)
     * - Record ID: Related Opportunity ID for traceability
     * 
     * Then bulk-inserts all logs in a single DML operation for efficiency.
     * 
     * Marked with @TestVisible to allow unit tests to call this private method directly.
     * 
     * @param oppIdToErrorDetails Map of Opportunity IDs → aggregated error message strings
     */
    @TestVisible
    private static void logErrors(Map<String, String> oppIdToErrorDetails) {
        List<Exception_Log__c> logsToInsert = new List<Exception_Log__c>();
        for (String oppId : oppIdToErrorDetails.keySet()) {
            Exception_Log__c log = ExceptionLogger.createInstance(
                'OpportunityTriggerHandler',
                new DmlException('Insert/Delete failed for Subscription records'),
                oppIdToErrorDetails.get(oppId),
                oppId
            );
            logsToInsert.add(log);
        }
        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }
}