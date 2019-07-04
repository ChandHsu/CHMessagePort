//
//  CHMessagePort.m
//  test
//
//  Created by ChandHsu on 2019/7/2.
//  Copyright © 2019 ChandHsu. All rights reserved.
//

#import "CHMessagePort.h"
#import <CoreFoundation/CFNotificationCenter.h>

/*
 问题日记:
 如果遇到发消息只能使用一次的问题,原因则是不能调用arc的某些东西,比如__bridge等等,不然会导致崩溃
 此时,可将此文件编译为MRC,(__bridge NSData *)data转为(NSData *)data等,去除所有关于__bridge的东西
 */

@interface CHMessageResponseObj : NSObject

@property (nonatomic,copy) NSString *notifyName;
@property (nonatomic,copy) CHResponseHandler responseHandler;
/* 剩余响应次数 */
@property (nonatomic,assign) int responseTimeOdd;

@end

@implementation CHMessageResponseObj

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.responseTimeOdd = MAXFLOAT;
    }
    return self;
}

@end

@interface CHMessagePort ()

@property (strong, nonatomic) dispatch_semaphore_t cfNotiLock;
@property (strong, nonatomic,nullable) NSDictionary *cfNotiResult;
@property (strong, nonatomic) NSMutableArray <CHMessageResponseObj *>*responseObjs;

@end

extern CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);
void CHCFNotificationReciveHandler(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo)
{
    
    NSString *notifyName = (__bridge NSString *)name;
    CHMessagePort *msgPort = [CHMessagePort sharedPort];
    
    CHMessageResponseObj *responseObj;
    for (CHMessageResponseObj *obj in msgPort.responseObjs) {
        if ([obj.notifyName isEqualToString:notifyName]) {
            responseObj = obj;
            break;
        }
    }
    if (!responseObj) return;
    
//    if(!CFDictionaryContainsKey(userInfo, (void *)@"data")) return;
    const void *data = CFDictionaryGetValue(userInfo, (void *)@"data");
//    if(!data) return;
    
    NSDictionary *notiInfo = [NSJSONSerialization JSONObjectWithData:(__bridge NSData *)data options:NSJSONReadingMutableLeaves error:nil];
    responseObj.responseTimeOdd --;
    responseObj.responseHandler(notifyName, notiInfo);
    if (responseObj<=0) [msgPort removeNotifyObserverWithName:notifyName];
}

@implementation CHMessagePort

- (NSMutableArray<CHMessageResponseObj *> *)responseObjs{
    if (!_responseObjs) {
        _responseObjs = [NSMutableArray array];
    }
    return _responseObjs;
}

static dispatch_once_t predicate;
+ (instancetype)sharedPort{
    static CHMessagePort *port = nil;
    dispatch_once(&predicate, ^{
        port = [[self alloc] init];
        [port afterInit];
    });
    return port;
}
- (void)afterInit{
    self.cfNotiLock = dispatch_semaphore_create(0);
    self.timeOut = 3;
}
- (void)releasePort{
    [self removeAllNotifyObserver];
    predicate = 0;
}

- (void)addCFNotificationCenterObserverNamed:(NSString *)name{
    CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
    CFNotificationCenterAddObserver(distributedCenter,
                                    (const void *)self,
                                    CHCFNotificationReciveHandler,
                                    (__bridge CFStringRef)name,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately
                                    );
}

- (void)addNotifyObserverWithName:(nonnull NSString *)name responseAction:(nonnull CHResponseHandler)responseHandler{
    [self addNotifyObserverWithName:name responseAction:responseHandler configHandler:nil];
}
- (void)addNotifyObserverWithName:(nonnull NSString *)name responseAction:(nonnull CHResponseHandler)responseHandler configHandler:(nullable void(^)(CHMessageResponseObj *))configHandler{
    
    CHMessageResponseObj *obj = [[CHMessageResponseObj alloc] init];
    obj.responseHandler = responseHandler;
    obj.notifyName = [NSString stringWithFormat:@"CHObserber_%@",name];
    [self.responseObjs addObject:obj];
    if(configHandler) configHandler(obj);
    [self addCFNotificationCenterObserverNamed:name];
}
- (void)removeNotifyObserverWithName:(nonnull NSString *)name{
    for (CHMessageResponseObj *obj in self.responseObjs) {
        if ([obj.notifyName isEqualToString:name]) {
            CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
            CFNotificationCenterRemoveObserver(distributedCenter, (const void *)self, (__bridge CFStringRef)name, NULL);
            [self.responseObjs removeObject:obj];
            return;
        }
    }
}
- (void)removeAllNotifyObserver{
    CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
    CFNotificationCenterRemoveEveryObserver(distributedCenter, (const void *)self);
    
    [self.responseObjs removeAllObjects];
}

- (void)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo{
    [self postNotifyWithName:name userInfo:userInfo waitForResponseNotifyWithName:nil];
}
- (nullable NSDictionary *)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo{
    return [self postNotifyWithName:name userInfo:userInfo waitForResponseNotifyWithName:name];
}
- (nullable NSDictionary *)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo waitForResponseNotifyWithName:(nullable NSString *)responseName{
    
    self.cfNotiResult = nil;
    
    if (responseName) {
        
        __weak typeof(self) weakSelf = self;
        
        [self addNotifyObserverWithName:responseName responseAction:^(NSString * _Nonnull notifyName, NSDictionary * _Nonnull responseDict){
            weakSelf.cfNotiResult = responseDict;
            weakSelf.cfNotiResult = [responseDict copy];
            dispatch_semaphore_signal(weakSelf.cfNotiLock);
        } configHandler:^(CHMessageResponseObj *obj) {
            obj.responseTimeOdd = 1;
        }];
    }
    
    //    CFStringRef notifyName = (CFStringRef)name;
    CFStringRef notifyName = (__bridge CFStringRef)name;
    CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
    
    void *object;
    CFMutableDictionaryRef userInfoRef = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, nil, nil);
    if (userInfo) {
        NSData *data= [NSJSONSerialization dataWithJSONObject:userInfo options:NSJSONWritingPrettyPrinted error:nil];
        CFDictionaryAddValue(userInfoRef, (__bridge void *)@"data", (__bridge void *)data);
        //        CFDictionaryAddValue(userInfoRef, (const void *)@"data", (const void *)data);
    }
    //    NSLog(@"哈利路亚");
    
    CFNotificationCenterPostNotification(distributedCenter,notifyName,object,userInfoRef,true);
    
    if (responseName) {
        dispatch_time_t duration = dispatch_time(DISPATCH_TIME_NOW, self.timeOut * NSEC_PER_SEC);
        dispatch_semaphore_wait(self.cfNotiLock,duration);
    }
    
    return self.cfNotiResult;
}

@end
