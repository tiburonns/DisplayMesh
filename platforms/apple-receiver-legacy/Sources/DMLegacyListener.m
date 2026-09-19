#import "DMLegacyListener.h"
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

static const uint16_t DMLegacyPort = 49655;

@interface DMLegacyListener ()
@property (nonatomic) int serverSocket;
@property (nonatomic) int clientSocket;
@property (nonatomic) uint32_t nextSequence;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_source_t serverSource;
@property (nonatomic, strong) dispatch_source_t clientSource;
@property (nonatomic, strong) DMLegacyFrameCodec *codec;
@property (nonatomic, strong) NSNetService *service;
@end

@implementation DMLegacyListener

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverSocket = -1;
        _clientSocket = -1;
        _nextSequence = 1;
        _queue = dispatch_queue_create("com.tiburonns.DisplayMesh.legacy.transport", DISPATCH_QUEUE_SERIAL);
        _codec = [[DMLegacyFrameCodec alloc] init];
    }
    return self;
}

- (BOOL)start:(NSError **)error {
    if (self.serverSocket >= 0) { return YES; }
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor < 0) {
        if (error) { *error = [self socketError:@"No se pudo crear el socket"] ; }
        return NO;
    }

    int yes = 1;
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(DMLegacyPort);
    address.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(descriptor, 1) < 0) {
        close(descriptor);
        if (error) { *error = [self socketError:@"No se pudo abrir el puerto 49655"] ; }
        return NO;
    }

    self.serverSocket = descriptor;
    self.serverSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, descriptor, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.serverSource, ^{
        [weakSelf acceptClient];
    });
    dispatch_source_set_cancel_handler(self.serverSource, ^{
        close(descriptor);
    });
    dispatch_resume(self.serverSource);

    self.service = [[NSNetService alloc] initWithDomain:@"local."
                                                   type:@"_displaymesh._tcp."
                                                   name:[UIDevice currentDevice].name
                                                   port:DMLegacyPort];
    [self.service publish];
    [self publishState:@"Esperando host en TCP 49655"];
    return YES;
}

- (void)stop {
    dispatch_async(self.queue, ^{
        [self closeClient];
        [self.service stop];
        self.service = nil;
        if (self.serverSource) {
            dispatch_source_cancel(self.serverSource);
            self.serverSource = nil;
        } else if (self.serverSocket >= 0) {
            close(self.serverSocket);
        }
        self.serverSocket = -1;
        [self publishState:@"Detenido"];
    });
}

- (void)disconnectClient {
    dispatch_async(self.queue, ^{ [self closeClient]; });
}

- (void)acceptClient {
    struct sockaddr_in peerAddress;
    socklen_t length = sizeof(peerAddress);
    int client = accept(self.serverSocket, (struct sockaddr *)&peerAddress, &length);
    if (client < 0) { return; }
    [self closeClient];
    self.clientSocket = client;
    int yes = 1;
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    [self.codec reset];

    char buffer[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &peerAddress.sin_addr, buffer, sizeof(buffer));
    NSString *peer = [NSString stringWithUTF8String:buffer] ?: @"host desconocido";

    self.clientSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, client, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.clientSource, ^{ [weakSelf readClient]; });
    dispatch_source_set_cancel_handler(self.clientSource, ^{ close(client); });
    dispatch_resume(self.clientSource);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate legacyListener:self didAcceptPeer:peer];
    });
    [self publishState:[NSString stringWithFormat:@"Conectado: %@", peer]];
}

- (void)readClient {
    uint8_t bytes[64 * 1024];
    ssize_t count = recv(self.clientSocket, bytes, sizeof(bytes), 0);
    if (count <= 0) {
        [self closeClient];
        [self publishState:@"Host desconectado"];
        return;
    }
    [self.codec appendData:[NSData dataWithBytes:bytes length:(NSUInteger)count]];
    while (YES) {
        NSError *error = nil;
        DMLegacyFrame *frame = [self.codec nextFrameWithError:&error];
        if (error) {
            [self publishState:error.localizedDescription];
            [self closeClient];
            return;
        }
        if (!frame) { break; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate legacyListener:self didReceiveFrame:frame];
        });
    }
}

- (void)sendType:(DMLegacyMessageType)type payload:(NSData *)payload {
    dispatch_async(self.queue, ^{
        if (self.clientSocket < 0) { return; }
        NSData *frame = [DMLegacyFrameCodec encodeType:type flags:0 sequence:self.nextSequence++ payload:payload];
        const uint8_t *bytes = frame.bytes;
        NSUInteger remaining = frame.length;
        while (remaining > 0) {
            ssize_t sent = send(self.clientSocket, bytes, remaining, 0);
            if (sent <= 0) { [self closeClient]; return; }
            bytes += sent;
            remaining -= (NSUInteger)sent;
        }
    });
}

- (void)closeClient {
    if (self.clientSource) {
        dispatch_source_cancel(self.clientSource);
        self.clientSource = nil;
    } else if (self.clientSocket >= 0) {
        close(self.clientSocket);
    }
    self.clientSocket = -1;
    [self.codec reset];
}

- (NSError *)socketError:(NSString *)description {
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:errno
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)publishState:(NSString *)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate legacyListener:self didChangeState:state];
    });
}

@end
