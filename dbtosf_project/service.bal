import ballerinax/salesforce;
import ballerina/http;

type Attributes record {
    string 'type;
    string url;
};

type ContactsItem record {
    string fullName;
    (anydata|string)? phoneNumber;
    (anydata|string)? email;
    string id;
};

type ContactsOutput record {
    int numberOfContacts;
    ContactsItem[] contacts;
};

type RecordsItem record {
    Attributes attributes;
    string Id;
    string FirstName;
    string LastName;
    (anydata|string)? Email;
    (anydata|string)? Phone;
};

type ContactsInput record {
    int totalSize;
    boolean done;
    RecordsItem[] records;
};

function transform(ContactsInput contactsInput) returns ContactsOutput => {
    numberOfContacts: contactsInput.totalSize,
    contacts: from var recordsItem in contactsInput.records
        select {
            fullName: recordsItem.FirstName + recordsItem.LastName,
            phoneNumber: recordsItem.Phone,
            email: recordsItem.Email,
            id: recordsItem.Id
        }
};

type SalesforceConfig record {|
    string baseUrl;
    string token;
|};

configurable SalesforceConfig sfConfig = ?;

salesforce:Client salesforceEp = check new (config = {
    baseUrl: sfConfig.baseUrl,
    auth: {
        token: sfConfig.token
    }
});

const string SALESFORCE_QUERY_FOR_CONTACTS = "SELECT Id,FirstName,LastName,Email,Phone FROM Contact";

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    # A resource for generating greetings
    # + name - the input string name
    # + return - string name with hello message or error
    resource function get greeting(string name) returns string|error {
        // Send a response back to the caller.
        if name is "" {
            return error("name should not be empty!");
        }
        return "Hello, " + name;
    }

    # A resource for transforming contacts
    # + contactsInput - The request payload with records to create Contacts
    # + return - Transformed Contacts collection or error
    resource function post contacts(@http:Payload ContactsInput contactsInput) returns ContactsOutput|error? {
        ContactsOutput contactsOutput = transform(contactsInput);
        return contactsOutput;
    }

    # A resource for fetching contacts from salesforce
    # + return - Contacts collection or error
    resource function get contacts() returns ContactsOutput|error? {
        salesforce:SoqlResult|salesforce:Error soqlResult = salesforceEp->getQueryResult(SALESFORCE_QUERY_FOR_CONTACTS);
        if (soqlResult is salesforce:SoqlResult) {

            json results = soqlResult.toJson();

            ContactsInput salesforceContactsResponse = check results.cloneWithType(ContactsInput);

            ContactsOutput contacts = transform(salesforceContactsResponse);

            return contacts;

        } else {
            return error(soqlResult.message());
        }
    }
}
