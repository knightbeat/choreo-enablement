import ballerina/io;
import edi_processor.sorder;
import ballerina/http;
import ballerina/ftp;

type FtpParams record {|
    string host;
    int port;
    string path;
    string username;
    string password;
|};

type HttpEndpointsParams record {|
    string dssEndpoint;
    string notificationsEndpoint;
|};

configurable FtpParams ftpParamsConfig = ?;
configurable HttpEndpointsParams httpEndpointsParamsConfig = ?;

ftp:AuthConfiguration authConfig = {
    credentials: {
        username: ftpParamsConfig.username,
        password: ftpParamsConfig.password
    }
};

// Listener to detect file changes in the FTP server
listener ftp:Listener remoteFTPServer = check new ({
    protocol: ftp:FTP,
    host: ftpParamsConfig.host,
    port: ftpParamsConfig.port,
    path: ftpParamsConfig.path,
    pollingInterval: 2,
    fileNamePattern: "(.*).edi",
    auth: authConfig
});

// FTP client to read the file content and other interactions
// ftp:ClientConfiguration ftpClientConfig = {
//     protocol: ftp:FTP,
//     host: "localhost",
//     port: 21,
//     auth: authConfig
// };

service on remoteFTPServer {
    remote function onFileChange(ftp:Caller caller, ftp:WatchEvent & readonly event) returns error? {

        foreach ftp:FileInfo addedFile in event.addedFiles {

            io:println("Added file path: " + addedFile.pathDecoded);

            stream<byte[] & readonly, io:Error?>|ftp:Error fileStream = caller->get(addedFile.pathDecoded);

            if fileStream is stream<byte[] & readonly, io:Error?> {

                record {|byte[] value;|}|io:Error? fileContentBytesRecord = fileStream.next();

                if (fileContentBytesRecord is record {|byte[] value;|}) {

                    string fileContent = check string:fromBytes(fileContentBytesRecord.value);
                    io:println(fileContent);

                    sorder:SimpleOrder|error simpleOrder = sorder:fromEdiString(fileContent);

                    if simpleOrder is sorder:SimpleOrder {
                        io:println("Order Id: ", simpleOrder.header.orderId);

                        foreach sorder:Items_Type item in simpleOrder.items {

                            //POST http://localhost:8290/services/ItemsDataService/items
                            //io:println("Item: ", item.item, ", Quantity: ", item.quantity);
                            json payload = {"_postitems": item};
                            map<string> headers = {"content-type": "text/javascript"};
                            io:println(payload.toJsonString());
                            http:Client|http:ClientError dssClient = new (httpEndpointsParamsConfig.dssEndpoint);
                            if (dssClient is http:Client) {
                                http:Response|http:ClientError post = dssClient->post("/services/ItemsDataService/items", payload, headers);
                                io:println(post);
                            }
                            http:Client|http:ClientError errorQueueClient = new (httpEndpointsParamsConfig.notificationsEndpoint);
                            if (errorQueueClient is http:Client) {
                                http:Response|http:ClientError post = errorQueueClient->post("/c4fa10d5-8ada-406c-91a6-4d0b67ca26de", payload, headers);
                                io:println(post);
                            }
                        }
                    } else {
                        json errorMessage = {"notification": "error", "message": simpleOrder.message()};
                        io:println(errorMessage);
                        http:Client|http:ClientError errorQueueClient = new (httpEndpointsParamsConfig.notificationsEndpoint);
                        if (errorQueueClient is http:Client) {
                            http:Response|http:ClientError post = errorQueueClient->post("/c4fa10d5-8ada-406c-91a6-4d0b67ca26de", errorMessage, {mime: "application/json"});
                            io:println(post);
                        }
                    }
                }
                check caller->delete(addedFile.pathDecoded);
            }

            // foreach string deletedFile in event.deletedFiles {
            //     io:println("Deleted file path: " + deletedFile);
            // }
        }
    }
}
