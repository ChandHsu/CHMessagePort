//
//  CHMessagePort.h
//  test
//
//  Created by ChandHsu on 2019/7/2.
//  Copyright © 2019 ChandHsu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface CHMessagePort : NSObject

/* 通信超时时间,单位为秒 */
@property (nonatomic,assign) float timeOut;

+ (instancetype)sharedPort;
- (void)releasePort;

- (void)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo;
- (void)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo callBack:(void(^)(NSDictionary *responseDict))callBack;
/* 必须在非主线程运行才能得到结果 */
- (nullable NSDictionary *)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo;

- (void)addNotifyObserverWithName:(nonnull NSString *)name handler:(id(^)(NSString *notifyName,NSDictionary *responseDict))handler;

- (void)removeNotifyObserverWithName:(nonnull NSString *)name;
- (void)removeAllNotifyObserver;

@end

NS_ASSUME_NONNULL_END
