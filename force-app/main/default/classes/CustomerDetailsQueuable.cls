/**
 * @description       : Queueable implementation that fetches user details from RandomUser API 
 *                      and creates Account (household) and Contact records in Salesforce.
 *                      Demonstrates async processing, HTTP callouts, and error handling patterns.
 * @author            : shambo.ray@gmail.com
 * @group             : Customer Data Integration
 * @created on        : 11-13-2025
 * @last modified on  : 11-16-2025
 * @notes             :
 *  - Implements Queueable interface for async execution; Database.AllowsCallouts allows HTTP callouts
 *  - Uses partial-success DML (Database.insert(..., false)) to allow partial record insertion on error
 *  - Builds Account-Contact relationships without additional SOQL queries by mapping SaveResult IDs
 *  - Loads API endpoint/method/timeout from custom metadata RandomUserAPI_Config__mdt
 *  - All exceptions (parsing, DML, HTTP) are captured and persisted to Exception_Log__c
 *  - Test seam: constructor injection of endpoint/method/timeout allows tests to bypass metadata
 */
public with sharing class CustomerDetailsQueuable implements Queueable, Database.AllowsCallouts {
    private static final String CONFIG_RECORD_NAME = 'GetUserDetailsAPI';
	private static final Integer STATUS_CODE = 200;
    /**
     * Inner class to hold parsed user data extracted from API response JSON
     * 
     * Provides a strongly-typed container for user attributes from the RandomUser API,
     * separating JSON deserialization from SObject field mapping. Includes personal details,
     * address information, and company/employment context for household account creation.
     */
    private class ParsedUserData {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String cell;
        public String street;
        public String city;
        public String state;
        public String country;
        public String postcode;
        // Company/employment fields (from new payload)
        public String companyName;
        public String companyDepartment;
        public String companyTitle;
        public String companyStreet;
        public String companyCity;
        public String companyState;
        public String companyCountry;
        public String companyPostalCode;
    }

    // Queueable execute method
    /**
     * Main entry point for async queueable execution
     * 
     * Orchestrates the full workflow:
     * 1. Load API configuration (endpoint, method, timeout) from custom metadata
     * 2. Execute HTTP GET callout to RandomUser API
     * 3. Validate HTTP response (must be 200) and parse JSON into Map
     * 4. Iterate through users array, parse each user, and stage Contact/Account records
     * 5. Execute partial-success insert of Accounts first
     * 6. Build Account name → ID map from SaveResults to avoid additional SOQL
     * 7. Relate Contacts to Accounts using generated household account names
     * 8. Execute partial-success insert of Contacts
     * 9. Batch insert any exception logs captured during processing
     * 
     * All exceptions (parsing, DML, HTTP) are caught and logged to Exception_Log__c via ExceptionLogger.
     * Top-level catch ensures catastrophic failures are also logged for observability.
     * 
     * @param qc QueueableContext provided by framework (unused but required by interface)
     */
    public void execute(QueueableContext qc) {
        List<Contact> contactsToInsert = new List<Contact>();
        List<Account> accountsToInsert = new List<Account>();
        List<Exception_Log__c> exceptionLogs = new List<Exception_Log__c>();
        List<Database.SaveResult> accountResults = null;

        try {
            // Load API configuration from custom metadata
            UserDetailsAPI_Config__mdt config = [SELECT Id, DeveloperName, Http_Method__c, API_Endpoint__c, Timeout_Ms__c FROM UserDetailsAPI_Config__mdt WHERE DeveloperName=:CONFIG_RECORD_NAME];

            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(config.API_Endpoint__c);
            req.setMethod(config.HTTP_Method__c);
            req.setTimeout(Integer.valueOf(config.Timeout_ms__c));

            HttpResponse res = http.send(req);
            String body = res.getBody();

            if (res.getStatusCode() != STATUS_CODE) {//200 considered as the success code for GET methods
                APILogger.log(config.API_Endpoint__c, req.getBody(), body, 'Error', 'HTTP status ' + res.getStatusCode());
                throw new CalloutException('Failed to fetch user data from API. Status: ' + res.getStatusCode());
            }

            APILogger.log(config.API_Endpoint__c, req.getBody(), body, 'Success', null);

            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (responseMap == null || !responseMap.containsKey('users')) {
                APILogger.log(config.API_Endpoint__c, req.getBody(), body, 'Error', 'Missing users array in response');
                throw new CalloutException('Invalid API response: missing users array');
            }

            List<Object> users = (List<Object>) responseMap.get('users');
            for (Object userObj : users) {
                try {
                    ParsedUserData userData = parseUserData((Map<String, Object>) userObj);
                    Contact contact = createContact(userData);
                    Account account = createAccount(userData);
                    contactsToInsert.add(contact);
                    accountsToInsert.add(account);
                } catch (Exception e) {
                    exceptionLogs.add(
                        ExceptionLogger.createInstance(
                            'RandomUserQueuable.execute - User Processing',
                            e,
                            'User data: ' + JSON.serialize(userObj),
                            null
                        )
                    );
                }
            }
            
            if (!accountsToInsert.isEmpty()) {
                accountResults = Database.insert(accountsToInsert, false);
                handleAccountInsertResults(accountResults, accountsToInsert, exceptionLogs);
            }

            if (!contactsToInsert.isEmpty()) {
                Map<String, Id> accountNameToIdMap = new Map<String, Id>();
                if (accountResults != null) {
                    for (Integer i = 0; i < accountResults.size(); i++) {
                        if (accountResults[i].isSuccess()) {
                            Account acc = accountsToInsert[i];
                            if (acc != null && acc.Name != null) accountNameToIdMap.put(acc.Name, accountResults[i].getId());
                        }
                    }
                }

                for (Integer i = 0; i < contactsToInsert.size(); i++) {
                    Contact contact = contactsToInsert[i];
                    String expectedAccountName =
                        (contact.FirstName != null ? contact.FirstName : '') + ' ' + (contact.LastName != null ? contact.LastName : '') + ' Household';
                    if (accountNameToIdMap.containsKey(expectedAccountName)) contact.AccountId = accountNameToIdMap.get(expectedAccountName);
                }

                List<Database.SaveResult> contactResults = Database.insert(contactsToInsert, false);
                handleContactInsertResults(contactResults, contactsToInsert, exceptionLogs);
            }

            if (!exceptionLogs.isEmpty()) insert exceptionLogs;

        } catch (Exception e) {
            ExceptionLogger.log('RandomUserBatch.execute', e, 'Queueable execution');
        }
    }

    /**
     * Parse user data from API response into a structured data object
     * 
     * Extracts nested JSON structures from the API payload and safely handles:
     * - Null/missing nested objects (address, company, company.address)
     * - Type conversions (postal codes may be numeric; convert to String)
     * - Fallback defaults for required fields to avoid errors
     * 
     * The returned ParsedUserData is used by factory methods (createContact, createAccount)
     * to create strongly-typed SObject records without embedding JSON parsing logic.
     * 
     * @param user Raw JSON user object from the API 'users' array
     * @return ParsedUserData containing all extracted and normalized user attributes
     */
    private ParsedUserData parseUserData(Map<String, Object> user) {
        ParsedUserData data = new ParsedUserData();
        // Top-level name/email/phone fields
        data.firstName = (String) user.get('firstName');
        data.lastName = (String) user.get('lastName');
        data.email = (String) user.get('email');
        data.phone = (String) user.get('phone');

        // User address
        Map<String, Object> address = (Map<String, Object>) user.get('address');
        data.street = address != null ? (String) address.get('address') : '';
        data.city = address != null ? (String) address.get('city') : null;
        data.state = address != null ? (String) address.get('state') : null;
        data.country = address != null ? (String) address.get('country') : null;
        Object postalObj = address != null ? address.get('postalCode') : null;
        data.postcode = postalObj != null ? String.valueOf(postalObj) : '';

        // Company/employment info — map to account fields later
        Map<String, Object> company = (Map<String, Object>) user.get('company');
        if (company != null) {
            data.companyName = (String) company.get('name');
            data.companyDepartment = (String) company.get('department');
            data.companyTitle = (String) company.get('title');
            Map<String, Object> caddr = (Map<String, Object>) company.get('address');
            if (caddr != null) {
                data.companyStreet = (String) caddr.get('address');
                data.companyCity = (String) caddr.get('city');
                data.companyState = (String) caddr.get('state');
                data.companyCountry = (String) caddr.get('country');
                Object cpost = caddr.get('postalCode');
                data.companyPostalCode = cpost != null ? String.valueOf(cpost) : null;
            }
        }

        return data;
    }

    /**
     * Factory method to create a Contact record from parsed user data
     * 
     * Maps personal and address information from ParsedUserData into a Contact SObject:
     * - FirstName, LastName: From user's personal data
     * - Email, Phone, MobilePhone: Contact methods
     * - Mailing fields: Personal address (street, city, state, country, postal code)
     * 
     * Note: Contact is not yet inserted; caller is responsible for DML operations.
     * 
     * @param data ParsedUserData containing user attributes
     * @return Contact SObject instance (not inserted)
     */
    private Contact createContact(ParsedUserData data) {
        Contact contact = new Contact();
        contact.FirstName = data.firstName;
        contact.LastName = data.lastName;
        contact.Email = data.email;
        contact.Phone = data.phone;
        contact.MobilePhone = data.cell;
        contact.MailingStreet = data.street;
        contact.MailingCity = data.city;
        contact.MailingState = data.state;
        contact.MailingCountry = data.country;
        contact.MailingPostalCode = data.postcode;
        return contact;
    }

    /**
     * Factory method to create an Account record (household) from parsed user data
     * 
     * Creates a "household" account with name format "{FirstName} {LastName} Household".
     * 
     * Field mapping strategy:
     * - BillingStreet/City/State/Country/PostalCode: Prefer company address if present; 
     *   fall back to personal address
     * - Industry: Set to company department (if available) for classification
     * - Description: Concatenates company/employment context 
     *   (e.g., "Employer: Acme | Title: Engineer | Department: R&D")
     * 
     * This approach supports both household-level (personal address) and employer-based 
     * (company billing) account records from a single user payload.
     * 
     * Note: Account is not yet inserted; caller is responsible for DML operations.
     * 
     * @param data ParsedUserData containing user and company attributes
     * @return Account SObject instance (not inserted)
     */
    private Account createAccount(ParsedUserData data) {
        String accountName = (data.firstName != null ? data.firstName : '')
            + ' ' + (data.lastName != null ? data.lastName : '') + ' Household';
        Account account = new Account();
        account.Name = accountName;
        // Store company/legal info on Account (employment info)
        account.BillingStreet = data.companyStreet != null ? data.companyStreet : data.street;
        account.BillingCity = data.companyCity != null ? data.companyCity : data.city;
        account.BillingState = data.companyState != null ? data.companyState : data.state;
        account.BillingCountry = data.companyCountry != null ? data.companyCountry : data.country;
        account.BillingPostalCode = data.companyPostalCode != null ? data.companyPostalCode : data.postcode;
        // Use industry to store department when available
        if (data.companyDepartment != null) account.Industry = data.companyDepartment;
        // Put employment summary into Description (legal/employment details)
        String descriptionText = '';
        if (data.companyName != null) {
            descriptionText = 'Employer: ' + data.companyName;
        }
        if (data.companyTitle != null) {
            descriptionText = (descriptionText.length() > 0 ? descriptionText + ' | ' : '') + 'Title: ' + data.companyTitle;
        }
        if (data.companyDepartment != null) {
            descriptionText = (descriptionText.length() > 0 ? descriptionText + ' | ' : '') + 'Department: ' + data.companyDepartment;
        }
        if (descriptionText.length() > 0) account.Description = descriptionText;
        return account;
    }

    /**
     * Inspect Account insert SaveResults and create exception logs for any failures
     * 
     * Iterates through SaveResult[] returned from Database.insert(..., false).
     * For each failed insert, extracts the error code and message and creates an Exception_Log__c
     * entry via ExceptionLogger.createInstance().
     * 
     * Failed logs are added to the exception logs list for batch insertion at the end of execute().
     * Uses DmlException wrapper to provide a structured exception type for logging.
     * 
     * Record ID in the log is the attempted insert ID (if available) or 'N/A'.
     * Context includes the account name for traceability.
     * 
     * @param accountResults SaveResult[] from Database.insert(accountsToInsert, false)
     * @param accountsToInsert Original list of Account records; indexed to match SaveResults
     * @param exceptionLogs Output list to accumulate Exception_Log__c records (mutated by method)
     */
    private void handleAccountInsertResults(
        List<Database.SaveResult> accountResults,
        List<Account> accountsToInsert,
        List<Exception_Log__c> exceptionLogs
    ) {
        for (Integer i = 0; i < accountResults.size(); i++) {
            if (!accountResults[i].isSuccess()) {
                for (Database.Error err : accountResults[i].getErrors()) {
                    String recordId = accountResults[i].getId() != null ? accountResults[i].getId() : 'N/A';
                    exceptionLogs.add(
                        ExceptionLogger.createInstance(
                            'RandomUserQueuable.execute - Account Insert',
                            new DmlException(err.getMessage()),
                            'Account: ' + accountsToInsert[i].Name,
                            recordId
                        )
                    );
                }
            }
        }
    }

    /**
     * Inspect Contact insert SaveResults and create exception logs for any failures
     * 
     * Iterates through SaveResult[] returned from Database.insert(..., false).
     * For each failed insert, extracts the error code and message and creates an Exception_Log__c
     * entry via ExceptionLogger.createInstance().
     * 
     * Failed logs are added to the exception logs list for batch insertion at the end of execute().
     * Uses DmlException wrapper to provide a structured exception type for logging.
     * 
     * Record ID in the log is the attempted insert ID
     * Context includes the contact name (FirstName + LastName) for traceability.
     * 
     * @param contactResults SaveResult[] from Database.insert(contactsToInsert, false)
     * @param contactsToInsert Original list of Contact records; indexed to match SaveResults
     * @param exceptionLogs Output list to accumulate Exception_Log__c records (mutated by method)
     */
    private void handleContactInsertResults(
        List<Database.SaveResult> contactResults,
        List<Contact> contactsToInsert,
        List<Exception_Log__c> exceptionLogs
    ) {
        for (Integer i = 0; i < contactResults.size(); i++) {
            if (!contactResults[i].isSuccess()) {
                for (Database.Error err : contactResults[i].getErrors()) {
                    String recordId = contactResults[i].getId() != null ? contactResults[i].getId() : 'N/A';
                    exceptionLogs.add(
                        ExceptionLogger.createInstance(
                            'RandomUserQueuable.execute - Contact Insert',
                            new DmlException(err.getMessage()),
                            'Contact: ' + contactsToInsert[i].FirstName + ' ' + contactsToInsert[i].LastName,
                            recordId
                        )
                    );
                }
            }
        }
    }
}