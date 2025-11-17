@isTest
public class SubscriptionControllerTest {
    
    @isTest
    static void testGetTableData() {
        // Create a subscription record (minimal fields) to be returned by the controller
        Subscription__c subscription = new Subscription__c(
            Name = 'Test Subscription'
        );
        insert subscription;

        // Use existing TableConfig custom metadata 'SubscriptionTable' provided with the package
        Test.startTest();
        Map<String, Object> result = SubscriptionController.getTableData(
            'SubscriptionTable', 
            null, 
            null, 
            1, 
            10
        );
        Test.stopTest();
        
    // Verify results
    System.assertNotEquals(null, result, 'Result map should not be null');
    System.assert(result.containsKey('columns'));
    System.assert(result.containsKey('records'));
    System.assert(result.containsKey('totalRecords'));
    // Ensure records is a list and totalRecords is non-negative
    List<Object> records = (List<Object>) result.get('records');
    System.assertNotEquals(null, records, 'Records should be a list');
    Integer total = (Integer) result.get('totalRecords');
    System.assert(total >= 0, 'totalRecords should be zero or positive');
    }
    
    @isTest
    static void testGetTableDataWithStatusFilter() {
        // Create subscription records with Status__c populated
        Subscription__c sub1 = new Subscription__c(
            Name = 'Active Subscription',
            Status__c = 'Active'
        );
        Subscription__c sub2 = new Subscription__c(
            Name = 'Inactive Subscription',
            Status__c = 'Inactive'
        );
        insert new List<Subscription__c>{sub1, sub2};

        // Use the package-provided TableConfig 'SubscriptionTable' which includes Status__c as a where condition
        Test.startTest();
        Map<String, Object> result = SubscriptionController.getTableData(
            'SubscriptionTable', 
            null, 
            'Active', 
            1, 
            10
        );
        Test.stopTest();
        
        // Verify results and that at least one returned row has Status__c = 'Active'
        System.assertNotEquals(null, result);
        System.assert(result.containsKey('columns'));
        System.assert(result.containsKey('records'));
        System.assert(result.containsKey('totalRecords'));
        List<Map<String, Object>> records = (List<Map<String, Object>>) result.get('records');
        Boolean foundActive = false;
        for (Map<String, Object> row : records) {
            if (row.containsKey('Status__c') && 'Active'.equals(String.valueOf(row.get('Status__c')))) {
                foundActive = true;
                break;
            }
        }
        System.assert(foundActive, 'At least one record with Status__c = Active should be returned by the filter');
    }
    
    @isTest
    static void testGetTableDataWithOptions() {
        // Use existing metadata 'SubscriptionTable' which includes Options__c in package; if options are not present,
        // the controller should return an empty list.
        Test.startTest();
        Map<String, Object> result = SubscriptionController.getTableData(
            'SubscriptionTable', 
            null, 
            null, 
            1, 
            10
        );
        Test.stopTest();
        
    // Verify results
    System.assertNotEquals(null, result);
    System.assert(result.containsKey('options'));
    List<Object> opts = (List<Object>) result.get('options');
    System.assertNotEquals(null, opts, 'Options key should be present (possibly empty)');
    }
}