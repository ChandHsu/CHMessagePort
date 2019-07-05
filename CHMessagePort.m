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

typedef void (^CHNotifyResponseHandler)(NSString *notifyName,NSDictionary *responseDict);

@interface CHMessageResponseObj : NSObject

@property (nonatomic,copy,nonnull) NSString *notifyName;
@property (nonatomic,copy,nullable) NSString *responseNotifyName;
@property (nonatomic,copy,nonnull) CHNotifyResponseHandler responseHandler;
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
void CHResponseHandler(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo)
{
    if(!CFDictionaryContainsKey(userInfo, (void *)@"data")) return;
    const void *data = CFDictionaryGetValue(userInfo, (void *)@"data");
    if(!data) return;
    
    NSDictionary *notiInfo = [NSJSONSerialization JSONObjectWithData:(__bridge NSData *)data options:NSJSONReadingMutableLeaves error:nil];
    
    CHMessagePort *port = [CHMessagePort sharedPort];
    port.cfNotiResult = [notiInfo copy];
    dispatch_semaphore_signal(port.cfNotiLock);
}
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
    
    const void *data = CFDictionaryGetValue(userInfo, (void *)@"data");
    const void *responseNotifyName = CFDictionaryGetValue(userInfo, (void *)@"responseNotifyName");
    if (responseNotifyName) responseObj.responseNotifyName = (__bridge NSString *)responseNotifyName;
    
    NSDictionary *notiInfo = [NSJSONSerialization JSONObjectWithData:(__bridge NSData *)data options:NSJSONReadingMutableLeaves error:nil];
    responseObj.responseTimeOdd --;
    responseObj.responseHandler(notifyName, notiInfo);
    if (responseObj<=0) [msgPort removeNotifyObserverWithName:notifyName];
}

@implementation CHMessagePort

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
    self.responseObjs = [NSMutableArray array];
    self.cfNotiLock = dispatch_semaphore_create(0);
    self.timeOut = 3;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
        CFNotificationCenterAddObserver(distributedCenter,
                                        (const void *)self,
                                        CHResponseHandler,
                                        (__bridge CFStringRef)[NSString stringWithFormat:@"CHObserver_%@",[NSProcessInfo processInfo].processName],
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately
                                        );
    });
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

- (void)addNotifyObserverWithName:(nonnull NSString *)name handler:(nonnull id(^)(NSString *,NSDictionary *))handler{
    [self addNotifyObserverWithName:name handler:handler configHandler:nil];
}
- (void)addNotifyObserverWithName:(nonnull NSString *)name handler:(nonnull id(^)(NSString *,NSDictionary *))handler configHandler:(nullable void(^)(CHMessageResponseObj *))configHandler{
    
    if (!(name&&handler)) return;
    
    CHMessageResponseObj *obj = [[CHMessageResponseObj alloc] init];
    
    __weak __typeof__(obj) weakObj = obj;
    obj.responseHandler = ^(NSString *notifyName, NSDictionary *responseDict) {
        id response = handler(notifyName,responseDict);
        NSString *responseNotifyName = weakObj.responseNotifyName;
        if (response&&responseNotifyName) {
            CFMutableDictionaryRef userInfoRef = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, nil, nil);
            NSData *reponseData= [NSJSONSerialization dataWithJSONObject:response?response:@{} options:NSJSONWritingPrettyPrinted error:nil];
            CFDictionaryAddValue(userInfoRef, (__bridge void *)@"data", (__bridge void *)reponseData);
            
            CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
            CFNotificationCenterPostNotification(distributedCenter,(__bridge CFStringRef)responseNotifyName,NULL,userInfoRef,true);
            NSLog(@"哈哈哈==远程回复结果==%@",responseNotifyName);
        }else{
            NSLog(@"哈哈哈==无需回复的通知");
        }
    };
    
    obj.notifyName = [name hasPrefix:@"CHObserver_"]?name:[NSString stringWithFormat:@"CHObserver_%@",name];
    [self.responseObjs addObject:obj];
    if(configHandler) configHandler(obj);
    [self addCFNotificationCenterObserverNamed:obj.notifyName];
    
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

/* 必须在非主线程执行 */
- (void)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo{
    [self postNotifyWithName:name userInfo:userInfo waitForResponseNotifyWithName:nil];
}
- (nullable NSDictionary *)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo{
    return [self postNotifyWithName:name userInfo:userInfo waitForResponseNotifyWithName:[NSProcessInfo processInfo].processName];
}
- (void)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo callBack:(void(^)(NSDictionary *responseDict))callBack{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSDictionary *dict = [self postNotifyWithName:name userInfo:userInfo waitForResponseNotifyWithName:[NSProcessInfo processInfo].processName];
        if (callBack) callBack(dict);
    });
}
- (nullable NSDictionary *)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo waitForResponseNotifyWithName:(nullable NSString *)responseNotifyName{
    
    name = [NSString stringWithFormat:@"CHObserver_%@",name];
    responseNotifyName = [NSString stringWithFormat:@"CHObserver_%@",responseNotifyName];
    
    self.cfNotiResult = nil;
    
    //    CFStringRef notifyName = (CFStringRef)name;
    CFStringRef notifyName = (__bridge CFStringRef)name;
    CFNotificationCenterRef distributedCenter = CFNotificationCenterGetDistributedCenter();
    
    __block void *object;
    CFMutableDictionaryRef userInfoRef = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, nil, nil);
    if (userInfo) {
        NSData *data= [NSJSONSerialization dataWithJSONObject:userInfo options:NSJSONWritingPrettyPrinted error:nil];
        
//        CFDictionaryAddValue(userInfoRef, (const void *)@"data", (const void *)data);
        CFDictionaryAddValue(userInfoRef, (__bridge void *)@"data", (__bridge void *)data);
        if (responseNotifyName) CFDictionaryAddValue(userInfoRef, (__bridge void *)@"responseNotifyName", (__bridge void *)responseNotifyName);
    }
    //    NSLog(@"哈利路亚");
    
    CFNotificationCenterPostNotification(distributedCenter,notifyName,object,userInfoRef,true);
    
    if (responseNotifyName) {
        dispatch_time_t duration = dispatch_time(DISPATCH_TIME_NOW, self.timeOut * NSEC_PER_SEC);
        dispatch_semaphore_wait(self.cfNotiLock,duration);
    }
    
    return self.cfNotiResult;
}

@end
