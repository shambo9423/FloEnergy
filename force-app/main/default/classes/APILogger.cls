/**
 * @description       : Utility class to capture API request/response details for observability and auditing.
 *                      Writes entries into the custom object API_Log__c.
 * @author            : shambo.ray@gmail.com
 * @group             :
 * @created on        : 11-13-2025
 * @last modified on  : 11-16-2025
 * @notes             :
 *  - Intended to be called by services performing callouts to external systems.
 *  - Use non-sensitive subsets of payloads where possible to avoid storing PII/Secrets.
**/
public with sharing class APILogger {

    /**
     * Log a single API interaction (request/response) into API_Log__c.
     *
     * @param endpoint       Fully qualified endpoint URL (or identifier) of the API.
     * @param requestBody    Request payload/body submitted to the API (if applicable).
     * @param responseBody   Response payload/body returned by the API (if applicable).
     * @param status         High-level status e.g. 'Success' or 'Error'.
     * @param errorMessage   Error/exception message if any; null when successful.
     */
    public static void log(String endpoint, String requestBody, String responseBody, String status, String errorMessage) {
        // Construct the API_Log__c record with all provided details
        API_Log__c entry = new API_Log__c();
        entry.Timestamp__c      = System.now();
        entry.API_Endpoint__c   = endpoint;
        entry.Request_Body__c   = requestBody;
        entry.Response_Body__c  = responseBody;
        entry.Status__c         = status;
        entry.Error_Message__c  = errorMessage;

        // Persist the log; using insert directly as this is a single-record utility call
        insert entry;
    }
}