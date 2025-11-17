/**
 * @description       : Centralized utility to capture and persist exception details to Exception_Log__c.
 *                      Used across the application to ensure consistent error observability.
 * @author            : shambo.ray@gmail.com
 * @group             :
 * @created on        : 11-13-2025
 * @last modified on  : 11-16-2025
 * @notes             :
 *  - Prefer createInstance(...) when batching many logs before a single DML insert.
**/
public with sharing class ExceptionLogger {

    /**
     * Convenience overload to log an exception without a related record Id.
     *
     * @param source       Logical source (class/method or feature area)
     * @param ex           The captured exception
     * @param contextData  Optional extra context (payloads, parameters)
     */
    public static void log(String source, Exception ex, String contextData) {
        log(source, ex, contextData, null);
    }
    
    /**
     * Log an exception and immediately insert the Exception_Log__c record.
     *
     * @param source       Logical source (class/method or feature area)
     * @param ex           The captured exception
     * @param contextData  Optional extra context (payloads, parameters)
     * @param recordId     Optional related record Id reference (if applicable)
     */
    public static void log(String source, Exception ex, String contextData, String recordId) {
        Exception_Log__c entry = createInstance(source, ex, contextData, recordId);
        insert entry;
    }
    
    /**
     * Factory method to build an Exception_Log__c instance without DML.
     * Useful for scenarios where multiple log entries are inserted in bulk.
     *
     * @param source       Logical source (class/method or feature area)
     * @param ex           The captured exception
     * @param contextData  Optional extra context (payloads, parameters)
     * @param recordId     Optional related record Id reference (if applicable)
     * @return Exception_Log__c (not yet inserted)
     */
    public static Exception_Log__c createInstance(String source, Exception ex, String contextData, String recordId) {
        // Populate the log record with rich exception details
        Exception_Log__c entry = new Exception_Log__c();
        entry.Timestamp__c        = System.now();
        entry.Source__c           = source;
        entry.Record_Id__c        = recordId;
        entry.Exception_Type__c   = ex.getTypeName();
        entry.Exception_Message__c= ex.getMessage();
        entry.Stack_Trace__c      = ex.getStackTraceString();
        entry.Context_Data__c     = contextData;
        return entry;
    }
}