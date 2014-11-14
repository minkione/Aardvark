//
//  ARKLogDistributorTests.m
//  Aardvark
//
//  Created by Dan Federman on 10/5/14.
//  Copyright (c) 2014 Square, Inc. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "ARKLogDistributor.h"
#import "ARKLogDistributor_Testing.h"
#import "ARKLogConsumer.h"
#import "ARKLogMessage.h"
#import "ARKLogStore.h"


@interface ARKLogDistributorTests : XCTestCase

@property (nonatomic, weak, readwrite) ARKLogDistributor *defaultLogDistributor;
@property (nonatomic, weak, readwrite) ARKLogStore *logStore;

@end


typedef void (^LogHandlingBlock)(ARKLogMessage *logMessage);


@interface ARKTestLogConsumer : NSObject <ARKLogConsumer>

@property (nonatomic, copy, readwrite) LogHandlingBlock logHandlingBlock;

@end


@implementation ARKTestLogConsumer

- (void)consumeLogMessage:(ARKLogMessage *)logMessage;
{
    if (self.logHandlingBlock) {
        self.logHandlingBlock(logMessage);
    }
}

@end


@interface ARKLogMessageTestSubclass : ARKLogMessage
@end

@implementation ARKLogMessageTestSubclass
@end


@implementation ARKLogDistributorTests

#pragma mark - Setup

- (void)setUp;
{
    [super setUp];
    
    self.defaultLogDistributor = [ARKLogDistributor defaultDistributor];
    
    ARKLogStore *logStore = [ARKLogStore new];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = paths.firstObject;
    logStore.persistedLogsFileURL = [NSURL fileURLWithPath:[[applicationSupportDirectory stringByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier] stringByAppendingPathComponent:@"ARKLogDistributorTests.data"]];
    
    [ARKLogDistributor setDefaultLogStore:logStore];
    
    self.logStore = logStore;
}

- (void)tearDown;
{
    [self.logStore clearLogs];
    
    // Wait for logs to be cleared.
    (void)[self.logStore allLogMessages];
    
    // Remove the default store.
    [ARKLogDistributor setDefaultLogStore:nil];
    
    [super tearDown];
}

#pragma mark - Behavior Tests

- (void)test_setLogMessageClass_appendedLogsAreCorrectClass;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    [logDistributor addLogConsumer:self.logStore];
    
    [logDistributor appendLogWithFormat:@"This log should be an ARKLogMessage"];
    
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    
    XCTAssertEqual(self.logStore.allLogMessages.count, 1);
    XCTAssertEqual([self.logStore.allLogMessages.firstObject class], [ARKLogMessage class]);
    
    [[ARKLogDistributor defaultLogStore] clearLogs];
    XCTAssertEqual(self.logStore.allLogMessages.count, 0);
    
    logDistributor.logMessageClass = [ARKLogMessageTestSubclass class];
    [logDistributor appendLogWithFormat:@"This log should be an ARKLogMessageTestSubclass"];
    
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    
    XCTAssertEqual(self.logStore.allLogMessages.count, 1);
    XCTAssertEqual([self.logStore.allLogMessages.firstObject class], [ARKLogMessageTestSubclass class]);
}

- (void)_test_appendLogWithFormat_callsLogConsumers;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    
    NSMutableArray *logConsumerTest = [NSMutableArray new];
    ARKTestLogConsumer *testLogConsumer = [ARKTestLogConsumer new];
    testLogConsumer.logHandlingBlock = ^(ARKLogMessage *logMessage) {
        [logConsumerTest addObject:logMessage];
    };
    [logDistributor addLogConsumer:testLogConsumer];
    
    [logDistributor appendLogWithFormat:@"Log"];
    
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    XCTAssertEqual(logConsumerTest.count, 1);
}

- (void)test_addLogConsumer_notifiesLogConsumerOnAppendLog;
{
    NSMutableArray *logConsumerTest = [NSMutableArray new];
    ARKTestLogConsumer *testLogConsumer = [ARKTestLogConsumer new];
    testLogConsumer.logHandlingBlock = ^(ARKLogMessage *logMessage) {
        [logConsumerTest addObject:logMessage];
    };
    [self.defaultLogDistributor addLogConsumer:testLogConsumer];
    
    XCTAssertEqual(logConsumerTest.count, 0);
    
    for (NSUInteger i  = 0; i < self.logStore.maximumLogMessageCount; i++) {
        ARKLog(@"Log %@", @(i));
    }
    
    [self.defaultLogDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    
    XCTAssertGreaterThan(self.logStore.allLogMessages.count, 0);
    [self.logStore.allLogMessages enumerateObjectsUsingBlock:^(ARKLogMessage *logMessage, NSUInteger idx, BOOL *stop) {
        XCTAssertEqualObjects(logMessage, logConsumerTest[idx]);
    }];
    
    [self.defaultLogDistributor removeLogConsumer:testLogConsumer];
}

- (void)test_removeLogHandler_removesLogConsumer;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    
    NSMutableArray *logConsumerTest = [NSMutableArray new];
    ARKTestLogConsumer *testLogConsumer = [ARKTestLogConsumer new];
    testLogConsumer.logHandlingBlock = ^(ARKLogMessage *logMessage) {
        [logConsumerTest addObject:logMessage];
    };
    
    [logDistributor addLogConsumer:testLogConsumer];
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    
    XCTAssertEqual(logDistributor.logConsumers.count, 1);
    
    [logDistributor removeLogConsumer:testLogConsumer];
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    
    XCTAssertEqual(logDistributor.logConsumers.count, 0);
    
    for (NSUInteger i  = 0; i < 100; i++) {
        [logDistributor appendLogWithFormat:@"Log %@", @(i)];
    }
    
    [logDistributor.logAppendingQueue waitUntilAllOperationsAreFinished];
    XCTAssertEqual(logConsumerTest.count, 0);
}

@end
