@isTest
public class ExceptionLoggerTest {
    
    @isTest
    static void testLogWithoutRecordId() {
        Test.startTest();
        ExceptionLogger.log(
            'TestClass.testMethod', 
            new TypeException('Test exception'), 
            'Test context data'
        );
        Test.stopTest();

        List<Exception_Log__c> logs = [SELECT Id, Source__c, Exception_Message__c FROM Exception_Log__c WHERE Source__c = 'TestClass.testMethod' LIMIT 1];
        System.assertEquals(1, logs.size(), 'Exception log should be created');
        System.assertEquals('TestClass.testMethod', logs[0].Source__c);
        System.assertNotEquals(null, logs[0].Exception_Message__c, 'Exception message should be set');
    }

    @isTest
    static void testLogWithRecordId() {
        Test.startTest();
        ExceptionLogger.log(
            'TestClass.testMethod', 
            new TypeException('Test exception'), 
            'Test context data', 
            '001000000000001'
        );
        Test.stopTest();

        List<Exception_Log__c> logs = [SELECT Id, Source__c, Record_Id__c FROM Exception_Log__c WHERE Source__c = 'TestClass.testMethod' ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals(1, logs.size(), 'Exception log with record ID should be created');
        System.assertEquals('TestClass.testMethod', logs[0].Source__c);
        System.assertEquals('001000000000001', logs[0].Record_Id__c);
    }

    @isTest
    static void testCreateInstance() {
        Exception_Log__c log = ExceptionLogger.createInstance(
            'TestClass.testMethod', 
            new TypeException('Test exception'), 
            'Test context data', 
            '001000000000001'
        );

        System.assertEquals('TestClass.testMethod', log.Source__c);
        System.assertEquals('001000000000001', log.Record_Id__c);
        System.assertNotEquals(null, log.Exception_Type__c);
        System.assertNotEquals(null, log.Exception_Message__c);
        System.assertNotEquals(null, log.Stack_Trace__c);
        System.assertEquals('Test context data', log.Context_Data__c);
    }
}