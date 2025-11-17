/**
 * @description       : Handles Opportunity trigger events to create Subscription records
 *                       when an Opportunity is closed as Won (via insert, update, or undelete)
 * @author            : shambo.ray@gmail.com
 * @group             : 
 * @last modified on  : 11-15-2025
**/
trigger OpportunityTrigger on Opportunity (after insert, after update, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            // Handle Opportunities created directly as Won
            OpportunityTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            // Handle Opportunities transitioned to Won status
            OpportunityTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUndelete) {
            // Handle restored Opportunities that are Won
            OpportunityTriggerHandler.handleAfterUndelete(Trigger.new);
        }
    }
}