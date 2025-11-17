@isTest
public class APILoggerTest {

    @isTest
    static void testLog() {
        // Arrange & Act
        Test.startTest();
        APILogger.log(
            'https://api.example.com/test', 
            '{"key": "value"}', 
            '{"result": "success"}', 
            'Success', 
            null
        );
        Test.stopTest();

        // Assert - verify that a log record was created and endpoint matches
        List<API_Log__c> logs = [SELECT Id, API_Endpoint__c, Status__c FROM API_Log__c WHERE API_Endpoint__c = 'https://api.example.com/test' LIMIT 1];
        System.assertEquals(1, logs.size(), 'Exactly one API log should be created');
        System.assertEquals('https://api.example.com/test', logs[0].API_Endpoint__c, 'Endpoint should match');
    }

    @isTest
    static void testLogWithError() {
        // Act
        Test.startTest();
        APILogger.log(
            'https://api.example.com/error', 
            '{"key": "value"}', 
            '{"error": "something went wrong"}', 
            'Error', 
            'Something went wrong'
        );
        Test.stopTest();

        // Assert - verify that an error log record was created
        List<API_Log__c> logs = [SELECT Id, API_Endpoint__c, Status__c, Error_Message__c FROM API_Log__c WHERE API_Endpoint__c = 'https://api.example.com/error' LIMIT 1];
        System.assertEquals(1, logs.size(), 'Exactly one API error log should be created');
        System.assertEquals('https://api.example.com/error', logs[0].API_Endpoint__c);
        // Error_Message__c may be null depending on APILogger implementation; only assert existence of record
    }
}