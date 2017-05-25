//
//  SIMPConnection.m
//  Hey
//
//  Created by Ascen on 2017/3/22.
//  Copyright © 2017年 Ascen. All rights reserved.
//

#import "SIMPConnection.h"
#import "SIMPConstants.h"
#import <sys/socket.h>
#import "Message.pbobjc.h"
#import "SIMPMessage.h"



@interface SIMPConnection () <GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate>

@property (nonatomic, assign) NSString *userID;

@end

@implementation SIMPConnection

//singleton
+ (instancetype)sharedConnection {
    static SIMPConnection *sharedConnection = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedConnection = [[self alloc] init];
    });
    return sharedConnection;
    
}

- (BOOL)connectionToRemoteHost:(NSString *)host port:(NSInteger)port forUser:(NSString *)userID {
    self.host = host;
    self.port = port;
    self.userID = userID;
    self.tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0)];
    self.udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    return [self connect];
}

- (BOOL)connect {
//    if (![self.tcpSocket isConnected] && ![self.udpSocket isConnected]) {
        NSError *error;
        BOOL tcpSuccess = [self.tcpSocket connectToHost:self.host onPort:self.port error:&error];
        NSLog(@"tcp conntect --%@", tcpSuccess ? @"YES" : @"NO");
        CheckError(@"TCPSocketConnectToHost", &error);
        
        
        BOOL udpSuccess = [self.udpSocket connectToHost:self.host onPort:self.port + 1 error:&error];
        
        CheckError(@"UDPSocketConnectToHost", &error);
        NSLog(@"udp conntect --%@", udpSuccess ? @"YES" : @"NO");
        [self.udpSocket beginReceiving:&error];
        CheckError(@"beginReceiving", &error);
        
        NSLog(@"----%@---%hu",self.tcpSocket.localHost, self.tcpSocket.localPort);
        NSLog(@"----%@---%hu",self.udpSocket.localHost, self.udpSocket.localPort);
        
        [self sendConnectData];
//    }
    return tcpSuccess && udpSuccess;
}

- (BOOL)isConnected {
    return [self.udpSocket isConnected] && [self.tcpSocket isConnected];
}

- (void)sendConnectData {
    Message *msg = [[Message alloc] init];
    msg.fromUser = self.userID;
    msg.version = SIMPVersion;
    msg.type = Message_MessageType_Connect;
    NSLog(@"UDP地址是: %@:%hu", _udpSocket.localHost, _udpSocket.localPort);
    msg.content = [NSString stringWithFormat:@"%@:%hu", _udpSocket.localHost, _udpSocket.localPort];
    [self.tcpSocket writeData:[msg data] withTimeout:5 tag:0];
}

- (void)sendMessage:(SIMPMessage *)msg {
//    Message *message = msg.message;
//    NSData *data = [message delimitedData];
    NSData *sendData = [msg.message data];
    if (msg.type == SIMPMessageTypeConnect) {
        [self.tcpSocket writeData:sendData withTimeout:10 tag:1];
    } else if (msg.type == SIMPMessageTypeText ||
               msg.type == SIMPMessageTypeImage ||
               msg.type == SIMPMessageTypeAudio) {
        [self.udpSocket sendData:sendData withTimeout:10 tag:2];
    }
}

- (void)dealloc {
}

- (NSData *)getCurrentAddress {
    if ([self.tcpSocket isConnected]) {
        return self.tcpSocket.localAddress;
    } else {
        return nil;
    }
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address {
    NSLog(@"socket--%@---didConnectToAddress----adress---%@",sock, address);
    [self.delegate connection:self didConnectToAdress:address bySocket:sock];
}


- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotConnect:(NSError * _Nullable)error {
    NSLog(@"socket--%@--didNotConnect----adress---%@",sock, error);
    [self.delegate connection:self didClosedWithError:error bySocket:sock];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
    NSLog(@"socket--%@---didSendDataWithTag---%ld",sock, tag);
    [self.delegate connection:self didSendMessageBySocket:sock];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError * _Nullable)error {

    NSLog(@"socket---%@---didNotSendDataWithTag---tag--%ld",sock, tag);
    [self.delegate connection:self didSendMessageFailedDueToError:error bySocket:sock];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(nullable id)filterContext {
    NSLog(@"didReceiveData----data--%@---adress---%@---filterContext---%@",data, address, filterContext);
    NSError *error;
    Message *message = [Message parseFromData:data error:&error];
    CheckError(@"parseFromData", &error);
    SIMPMessage *simpMessage = [[SIMPMessage alloc] initWithMessage:message];
    [self.delegate connection:self didReceiveMessage:simpMessage bySocket:sock];
    
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError  * _Nullable)error {
    NSLog(@"udpSocketDidClose----socket--%@---adress---%@",sock, error);
    [self.delegate connection:self didClosedWithError:error bySocket:sock];
}

#pragma mark - GCDAsyncSocketDelegate

- (nullable dispatch_queue_t)newSocketQueueForConnectionFromAddress:(NSData *)address onSocket:(GCDAsyncSocket *)sock {
    NSLog(@"%s",__func__);
    return nil;
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    NSLog(@"%s",__func__);
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"socket--%@---didConnectToHost---%@---port--%hu",sock, host, port);
    NSString *adress =  [host stringByAppendingString:[NSString stringWithFormat:@":%hu", port]];
    [self.delegate connection:self didConnectToAdress:[adress dataUsingEncoding:NSUTF8StringEncoding] bySocket:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToUrl:(NSURL *)url {
    NSLog(@"socket--%@---didConnectToUrl----url---%@",sock, url);
    [self.delegate connection:self didConnectToAdress:[[url absoluteString] dataUsingEncoding:NSUTF8StringEncoding] bySocket:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"socket--%@---didReadData----data---%@---tag---%ld",sock, data, tag);
    NSError *error;
    Message *message = [Message parseFromData:data error:&error];
    SIMPMessage *simpMessage = [[SIMPMessage alloc] initWithMessage:message];
    [self.delegate connection:self didReceiveMessage:simpMessage bySocket:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag {
    NSLog(@"%s",__func__);
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"socket--%@---didWriteDataWithTag----tag---%ld",sock, tag);
    [self.delegate connection:self didSendMessageBySocket:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag {
    NSLog(@"%s",__func__);
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
    NSLog(@"%s",__func__);
    return 0;
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutWriteWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
    NSLog(@"%s",__func__);
    return 0;
}

- (void)socketDidCloseReadStream:(GCDAsyncSocket *)sock {
    NSLog(@"socket--%@---socketDidCloseReadStream", sock);
    [self.delegate connection:self didClosedWithError:nil bySocket:sock];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err {
    NSLog(@"socket--%@---socketDidDisconnectWithError----%@", sock, err);
    [self.delegate connection:self didClosedWithError:err bySocket:sock];
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock {
    NSLog(@"%s",__func__);
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveTrust:(SecTrustRef)trust
completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler {
    NSLog(@"%s",__func__);
}

@end
