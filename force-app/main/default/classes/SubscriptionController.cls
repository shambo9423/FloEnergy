/**
 * @description       : Generic table controller for LWC datatable, driven by TableConfig__mdt.
 *                      Supports metadata-defined SOQL queries and WHERE conditions. Returns a shape
 *                      consumable by lightning-datatable including columns, records, record links, and totals.
 * @author            : shambo.ray@gmail.com
 * @group             :
 * @created on        : 11-15-2025
 * @last modified on  : 11-16-2025
 * @notes             :
 *  - BaseQuery__c should include only the fields required by the UI. This class projects only those fields.
 *  - WhereConditions__c defines param-driven filters (e.g., parentId, statusFilter).
 *  - Columns__c is JSON for lightning-datatable columns. Url-type columns may reference a label field.
**/
public with sharing class SubscriptionController {
    /**
     * Build table data from TableConfig__mdt definition.
     *
     * @param configName    DeveloperName of TableConfig__mdt
     * @param parentId      Optional parent record context (used by WhereConditions__c)
     * @param statusFilter  Optional status filter (used by WhereConditions__c)
     * @param page          1-based page number
     * @param perPage       Page size (default 10)
     * @return Map with keys: columns (List<Object>), objectApiName (String), totalRecords (Integer), records (List<Map>)
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTableData(String configName, Id parentId, String statusFilter, Integer page, Integer perPage) {
        Map<String, Object> result = new Map<String, Object>();

        // Fetch config and basic result scaffolding
        TableConfig__mdt config = fetchConfig(configName);
        if (config == null) return result;

        // Normalize pagination params
        if (perPage == null || perPage <= 0) perPage = config.Per_Page_Size__c!=null ? Integer.valueOf(config.Per_Page_Size__c):10;
        if (page == null || page <= 0) page = 1;
        Integer offset = (page - 1) * perPage;

        String objectApiName = config.ObjectApiName__c;
        List<Object> columns = (List<Object>) JSON.deserializeUntyped(config.Columns__c);
        result.put('columns', columns);
        result.put('objectApiName', objectApiName);
        result.put('options', String.isBlank(config.Options__c) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(config.Options__c));

    // Parse the JSON-configured WHERE conditions (if any). The metadata contains an
    // array of objects like { "field": "Subscription__c.Opportunity__c", "param": "parentId" }
    // which we convert into a List<Object> for downstream processing.
    List<Object> whereConditions = parseWhereConditions(config.WhereConditions__c);

        Map<String, Object> queryParams = new Map<String, Object>();
        List<String> whereClauses = buildWhereClauses(whereConditions, parentId, statusFilter, queryParams);

        String soql = buildSoql(config.BaseQuery__c, whereClauses) + ' ORDER BY Name LIMIT :perPage OFFSET :offset';
        queryParams.put('perPage', perPage);
        queryParams.put('offset', offset);

        String countSoql = buildCountSoql(objectApiName, whereClauses);

    // Execute queries (user mode to respect FLS/CRUD/sharing)
        Integer total = (Integer) Database.countQueryWithBinds(countSoql, queryParams, AccessLevel.USER_MODE);
        result.put('totalRecords', total);

        List<SObject> records = (List<SObject>) Database.queryWithBinds(soql, queryParams, AccessLevel.USER_MODE);

    // Determine projected fields and label fields from columns metadata
        Map<String, Set<String>> projected = determineProjectedFields(columns);
        Set<String> projectedFields = projected.get('projected');
        Set<String> labelFields = projected.get('labels');

        List<Map<String, Object>> rows = projectRecords(records, projectedFields, labelFields);
        result.put('records', rows);
        return result;
    }

    // --- Helper methods to modularize responsibilities ---
    /**
     * Load the TableConfig custom metadata record by DeveloperName.
     * Returns null if the metadata record is not present or a query error occurs.
     * Keeping this in a small helper isolates metadata access and makes testing easier.
     */
    private static TableConfig__mdt fetchConfig(String configName) {
        try {
            return [SELECT ObjectApiName__c, Columns__c, BaseQuery__c, WhereConditions__c, Per_Page_Size__c, Options__c FROM TableConfig__mdt WHERE DeveloperName = :configName LIMIT 1];
        } catch (Exception e) {
            // Swallow and return null so caller can handle absence of configuration gracefully
            return null;
        }
    }

    /**
     * Parse the JSON stored in WhereConditions__c into a List<Object>.
     * Returns an empty list when the JSON is blank.
     */
    private static List<Object> parseWhereConditions(String whereJson) {
        if (String.isBlank(whereJson)) return new List<Object>();
        return (List<Object>) JSON.deserializeUntyped(whereJson);
    }

    /**
     * Translate metadata-driven conditions into SOQL WHERE clauses using bind variable
     * placeholders and populate the provided queryParams map with values for those binds.
     * Supported params: 'parentId' and 'statusFilter'.
     */
    private static List<String> buildWhereClauses(List<Object> whereConditions, Id parentId, String statusFilter, Map<String, Object> queryParams) {
        List<String> whereClauses = new List<String>();
        for (Object condition : whereConditions) {
            Map<String,Object> cond = (Map<String,Object>)condition;
            String field = (String) cond.get('field');
            String param = (String) cond.get('param');

            if ('parentId'.equals(param) && parentId != null) {
                whereClauses.add(field + ' = :parentId');
                queryParams.put('parentId', parentId);
            } else if ('statusFilter'.equals(param) && !String.isBlank(statusFilter)) {
                whereClauses.add(field + ' = :statusFilter');
                queryParams.put('statusFilter', statusFilter);
            }
        }
        return whereClauses;
    }

    /**
     * Combine a base query (expected to be a SELECT ... FROM ... clause) with the
     * dynamic WHERE clauses produced by metadata, returning a SOQL string ready for
     * pagination (caller appends ORDER/LIMIT/OFFSET).
     */
    private static String buildSoql(String baseQuery, List<String> whereClauses) {
        String soql = baseQuery;
        if (!whereClauses.isEmpty()) {
            soql += ' WHERE ' + String.join(whereClauses, ' AND ');
        }
        return soql;
    }

    /**
     * Build a simple COUNT() SOQL using the target object API name and optional WHERE clauses.
     * This is used to compute the total number of matching rows for pagination.
     */
    private static String buildCountSoql(String objectApiName, List<String> whereClauses) {
        String countSoql = 'SELECT count() FROM ' + objectApiName;
        if (!whereClauses.isEmpty()) {
            countSoql += ' WHERE ' + String.join(whereClauses, ' AND ');
        }
        return countSoql;
    }

    /**
     * Analyze the configured columns JSON and return two sets:
     * - 'projected': the field API names that should be included in each row
     * - 'labels': additional label fields referenced by URL columns' typeAttributes
     *
     * This ensures the controller only projects the fields the UI expects.
     */
    private static Map<String, Set<String>> determineProjectedFields(List<Object> columns) {
        Set<String> projectedFields = new Set<String>();
        Set<String> labelFields = new Set<String>();
        for (Object colObj : columns) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            Object fn = col.get('fieldName');
            if (fn == null) fn = col.get('fieldApiName');
            if (fn != null) {
                String fieldName = String.valueOf(fn).trim();
                if (!String.isBlank(fieldName)) projectedFields.add(fieldName);
            }
            if ('url'.equalsIgnoreCase((String)col.get('type')) && col.containsKey('typeAttributes')) {
                Map<String, Object> ta = (Map<String, Object>) col.get('typeAttributes');
                if (ta != null && ta.containsKey('label')) {
                    Object labelObj = ta.get('label');
                    if (labelObj instanceof Map<String, Object>) {
                        Map<String, Object> labelMap = (Map<String, Object>) labelObj;
                        Object labelFieldNameObj = labelMap.get('fieldName');
                        if (labelFieldNameObj != null) {
                            String labelFieldName = String.valueOf(labelFieldNameObj).trim();
                            if (!String.isBlank(labelFieldName)) {
                                labelFields.add(labelFieldName);
                                projectedFields.add(labelFieldName);
                            }
                        }
                    }
                }
            }
        }
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        out.put('projected', projectedFields);
        out.put('labels', labelFields);
        return out;
    }

    /**
     * Transform raw SObject records returned by a dynamic SOQL into serializable row
     * maps that the LWC expects. Only fields listed in 'projectedFields' are included
     * (plus a 'recordLink'). Relationship dot-paths (e.g., 'Opportunity.Name') are
     * supported for single-level relationships.
     */
    private static List<Map<String, Object>> projectRecords(List<SObject> records, Set<String> projectedFields, Set<String> labelFields) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (SObject rec : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (String fieldName : projectedFields) {
                Object val = null;
                if (fieldName != null && fieldName.contains('.')) {
                    List<String> parts = fieldName.split('\\.');
                    if (parts.size() == 2) {
                        String relName = parts[0];
                        String relField = parts[1];
                        SObject rel = (SObject) rec.getSObject(relName);
                        if (rel != null) {
                            try { val = rel.get(relField); } catch (Exception ignore) { val = null; }
                        }
                    } else {
                        try { val = rec.get(fieldName); } catch (Exception ignore) { val = null; }
                    }
                } else {
                    try { val = rec.get(fieldName); } catch (Exception ignore) { val = null; }
                }
                row.put(fieldName, val);
            }
            // Provide a stable navigation link used by the UI for row actions
            row.put('recordLink', '/lightning/r/' + rec.get('Id') + '/view');

            // Ensure label fields referenced by url columns are present on the row
            for (String labelField : labelFields) {
                if (!row.containsKey(labelField)) {
                    Object labelVal = null;
                    try { labelVal = rec.get(labelField); } catch (Exception ignore) { labelVal = null; }
                    row.put(labelField, labelVal);
                }
            }
            rows.add(row);
        }
        return rows;
    }

}