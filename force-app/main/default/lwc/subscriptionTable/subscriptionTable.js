import { LightningElement, api, track } from 'lwc';
import getTableData from '@salesforce/apex/SubscriptionController.getTableData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * SubscriptionTable Component
 * Displays a table of subscription records related to an opportunity
 * Provides filtering and pagination capabilities
 */
export default class SubscriptionTable extends LightningElement {
    @api recordId;              // Opportunity ID to filter subscriptions
    @api configName;            // Name of TableConfig__mdt record to drive the table
    @api tableHeader;           // Header text for the card component
    @api perPage;               // Number of records per page
    @api filterName;            // Label for the status filter combobox

    // Component state variables
    @track statusFilter = '';   // Currently selected status filter
    @track page = 1;            // Current page number
    @track totalRecords = 0;    // Total number of records matching filter criteria
    @track records = [];        // Current page of records to display
    @track columns = [];        // Column definitions for the data table
    @track isLoading = false;   // Loading state indicator
    @track options = [];        // Options for status filter combobox

    /**
     * Determines if the current page is the first page
     * @returns {Boolean} True if on first page, false otherwise
     */
    get isFirstPage() {
        return this.page === 1;
    }

    /**
     * Determines if the current page is the last page
     * @returns {Boolean} True if on last page, false otherwise
     */
    get isLastPage() {
        const maxPage = Math.ceil(this.totalRecords / this.perPage);
        return this.page >= maxPage;
    }

    /**
     * Gets page information text for display
     * @returns {String} Text indicating current page range and total records
     */
    get pageInfo() {
        // When there are 0 records, display "0 to 0 of 0"
        if (this.totalRecords === 0) {
            return `Showing 0 to 0 of 0`;
        }
        const startRecord = (this.page - 1) * this.perPage + 1;
        const endRecord = Math.min(this.page * this.perPage, this.totalRecords);
        return `Showing ${startRecord} to ${endRecord} of ${this.totalRecords}`;
    }

    /**
     * Lifecycle callback when component is connected to DOM
     * Loads initial table data
     */
    connectedCallback() {
        this.loadTableData();
    }

    /**
     * Loads table data from Apex controller
     * Fetches subscription records for the opportunity with current filters
     */
    loadTableData() {
        if (!this.recordId || !this.configName) {
            this.showToast('Warning', 'Record ID and Config Name are required', 'warning');
            return;
        }
        this.isLoading = true;
        getTableData({
            configName: this.configName,
            parentId: this.recordId,
            statusFilter: this.statusFilter,
            page: this.page,
            perPage: this.perPage
        })
            .then(result => {
                this.columns = result.columns;
                this.records = result.records;
                this.options = result.options;
                this.totalRecords = result.totalRecords;
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            });
    }

    /**
     * Handles status filter change event
     * Resets to first page and reloads data with new filter
     * @param {Event} event - Change event from combobox
     */
    handleStatusChange(event) {
        this.statusFilter = event.target.value;
        this.page = 1;
        this.loadTableData();
    }

    /**
     * Navigates to previous page if available
     */
    handlePrev() {
        if (this.page > 1) {
            this.page--;
            this.loadTableData();
        }
    }

    /**
     * Navigates to next page if available
     */
    handleNext() {
        const maxPage = Math.ceil(this.totalRecords / this.perPage);
        if (this.page < maxPage) {
            this.page++;
            this.loadTableData();
        }
    }

    /**
     * Shows toast notification to user
     * @param {String} title - Toast title
     * @param {String} message - Toast message
     * @param {String} variant - Toast variant (success, error, warning, info)
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}