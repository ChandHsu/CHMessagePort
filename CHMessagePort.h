//
//  CHMessagePort.h
//  test
//
//  Created by ChandHsu on 2019/7/2.
//  Copyright © 2019 ChandHsu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^CHResponseHandler)(NSString *notifyName,NSDictionary *responseDict);

@interface CHMessagePort : NSObject

/* 通信超时时间,单位为秒 */
@property (nonatomic,assign) float timeOut;

+ (instancetype)sharedPort;
- (void)releasePort;

- (void)postNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo;
- (nullable NSDictionary *)postResponsiveNotifyWithName:(nonnull NSString *)name userInfo:(nullable NSDictionary *)userInfo;

- (void)addNotifyObserverWithName:(nonnull NSString *)name responseAction:(nonnull CHResponseHandler)responseHandler;

- (void)removeNotifyObserverWithName:(nonnull NSString *)name;
- (void)removeAllNotifyObserver;

@end

NS_ASSUME_NONNULL_END
