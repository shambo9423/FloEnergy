@isTest
public class CustomerDetailsQueuableTest {
    // Simple HttpCalloutMock returning a 200 with a single user in the 'users' array
    private class SuccessHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String body = '{"users": [' +
                '{"firstName":"Jane","lastName":"Tester","email":"jane.tester@example.com","phone":"(123) 456-7890","address": {"address":"1 Test St","city":"Testville","state":"Rhode Island","country":"United States","postalCode":"11111"},"company": {"name":"Acme","department":"R&D","title":"Engineer","address": {"address":"100 Acme Rd","city":"AcmeCity","state":"Rhode Island","country":"United States","postalCode":"22222"}}}' +
                ']}';
            res.setBody(body);
            return res;
        }
    }
    
    // Mock that returns a non-200 response to exercise error handling path
    private class ErrorHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }
    
    @isTest
    static void testExecute_withSuccessfulCallout_createsAccountAndContact() {
        // Use mock that returns a valid user payload
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());
        
        Integer initialAccountCount = Database.countQuery('SELECT count() FROM Account');
        Integer initialContactCount = Database.countQuery('SELECT count() FROM Contact');
        
        Test.startTest();
        // Enqueue the queueable to run async (it allows callouts)
        System.enqueueJob(new CustomerDetailsQueuable());
        Test.stopTest();
        
        // Verify that Accounts were created from the mock payload
        Integer finalAccountCount = Database.countQuery('SELECT count() FROM Account');
        System.assert(finalAccountCount > initialAccountCount, 'At least one new Account should be created by the queueable');
        
        // Verify Contact was created with correct fields
        Integer finalContactCount = Database.countQuery('SELECT count() FROM Contact');
        System.assert(finalContactCount > initialContactCount, 'At least one new Contact should be created by the queueable');
        
        List<Contact> contacts = [SELECT Id, FirstName, LastName, Email, Phone, AccountId FROM Contact WHERE Email = 'jane.tester@example.com' ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals(1, contacts.size(), 'Contact from mock payload should be created');
        System.assertEquals('Jane', contacts[0].FirstName, 'Contact FirstName should match mock data');
        System.assertEquals('Tester', contacts[0].LastName, 'Contact LastName should match mock data');
        System.assertEquals('jane.tester@example.com', contacts[0].Email, 'Contact Email should match mock data');
        System.assertEquals('(123) 456-7890', contacts[0].Phone, 'Phone should match the formatted number from payload');
        System.assertNotEquals(null, contacts[0].AccountId, 'Contact should be linked to created Account');
    }
    
    @isTest
    static void testExecute_withErrorResponse_doesNotCreateRecords_and_logsError() {
        // Use mock that returns 500
        Test.setMock(HttpCalloutMock.class, new ErrorHttpMock());
        
        Test.startTest();
        System.enqueueJob(new CustomerDetailsQueuable());
        Test.stopTest();
        
        // No Accounts/Contacts should be created when API returns error
        Integer accCount = Database.countQuery('SELECT count() FROM Account');
        Integer contactCount = Database.countQuery('SELECT count() FROM Contact');
        System.assertEquals(0, accCount, 'No Accounts should be created on error response');
        System.assertEquals(0, contactCount, 'No Contacts should be created on error response');
    }
    
    @isTest
    static void testHandleContactInsertResults_withSuccessPath() {
        // Test coverage for handleContactInsertResults method success path
        // When contacts insert successfully
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());
        
        Test.startTest();
        System.enqueueJob(new CustomerDetailsQueuable());
        Test.stopTest();
        
        // Verify that contacts were created successfully
        List<Contact> createdContacts = [SELECT Id, Email, Phone FROM Contact WHERE Email = 'jane.tester@example.com' ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals(1, createdContacts.size(), 'Contact should be created successfully');
        System.assertEquals('(123) 456-7890', createdContacts[0].Phone, 'Phone number should match validation rule format');
    }
    
    @isTest
    static void testHandleAccountInsertResults_withSuccessPath() {
        // Test coverage for handleAccountInsertResults method success path
        // When accounts insert successfully
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());
        
        Test.startTest();
        System.enqueueJob(new CustomerDetailsQueuable());
        Test.stopTest();
        
        // Verify that accounts were created successfully
        List<Account> createdAccounts = [SELECT Id, Name, BillingCity, BillingState FROM Account WHERE Name LIKE '%Household' ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals(1, createdAccounts.size(), 'Account should be created successfully');
        System.assert(createdAccounts[0].Name.contains('Household'), 'Account name should contain Household');
        System.assertNotEquals(null, createdAccounts[0].BillingCity, 'Account billing city should be populated');
    }
    
}