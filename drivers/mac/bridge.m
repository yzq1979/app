#include "bridge.h"
#include "_cgo_export.h"
#include "driver.h"
#include "json.h"

bridge_result make_bridge_result(NSString *payload, NSString *err) {
  bridge_result res;

  res.payload = nil;
  if (payload != nil) {
    res.payload = copyNSString(payload);
  }

  res.err = nil;
  if (err != nil) {
    res.err = copyNSString(err);
  }

  return res;
}

char *copyNSString(NSString *str) {
  int len = strlen(str.UTF8String) + 1;
  char *ret = calloc(len, sizeof(char));
  strcpy(ret, str.UTF8String);
  return ret;
}

bridge_result macosRequest(char *rawurl, char *cpayload) {
  NSString *urlstr = [NSString stringWithUTF8String:rawurl];
  free(rawurl);

  NSString *payload = nil;
  if (cpayload != nil) {
    payload = [NSString stringWithUTF8String:cpayload];
    free(cpayload);
  }

  NSURLComponents *url = [NSURLComponents componentsWithString:urlstr];
  Driver *driver = [Driver current];

  OBJCHandler handler = driver.objc.handlers[url.path];
  if (handler == nil) {
    NSString *err = [NSString stringWithFormat:@"%@ is not handled", url.path];
    return make_bridge_result(nil, err);
  }

  return handler(url, payload);
}

@implementation OBJCBridge
- (instancetype)init {
  self = [super init];
  self.handlers = [NSMutableDictionary dictionaryWithCapacity:32];
  return self;
}

- (void)handle:(NSString *)path handler:(OBJCHandler)handler {
  self.handlers[path] = handler;
}

- (void)asyncReturn:(NSString *)id result:(bridge_result)res {
  macosRequestResult(copyNSString(id), res);
}
@end

@implementation GoBridge
- (void)request:(NSString *)path payload:(NSString *)payload {
  char *p = nil;
  if (payload != nil) {
    p = (char *)payload.UTF8String;
  }

  goRequest((char *)path.UTF8String, p);
}

- (NSString *)requestWithResult:(NSString *)path payload:(NSString *)payload {
  char *p = nil;
  if (payload != nil) {
    p = (char *)payload.UTF8String;
  }

  char *cres = goRequestWithResult((char *)path.UTF8String, p);
  NSString *res = nil;
  if (cres != nil) {
    res = [NSString stringWithUTF8String:cres];
    free(cres);
  }
  return res;
}
@end

@implementation NSURLComponents (Queryable)
- (NSString *)queryValue:(NSString *)name {
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", name];
  NSURLQueryItem *queryItem =
      [[self.queryItems filteredArrayUsingPredicate:predicate] firstObject];
  return queryItem.value;
}
@end

// --------------- NEW -----------------------

void macCall(char *rawCall) {
  NSDictionary *call =
      [JSONDecoder decodeObject:[NSString stringWithUTF8String:rawCall]];

  NSString *method = call[@"Method"];
  NSDictionary *in = call[@"Input"];
  NSString *returnID = call[@"ReturnID"];

  @try {
    Driver *driver = [Driver current];
    MacRPCHandler handler = driver.macRPC.handlers[method];

    if (handler == nil) {
      @throw [NSException
          exceptionWithName:@"ErrMethodNotHandled"
                     reason:[NSString
                                stringWithFormat:@"%@ is not handled", method]
                   userInfo:nil];
    }

    handler(in);
  } @catch (NSException *exception) {
    NSString *err = exception.reason;
    macCallReturn((char *)returnID.UTF8String, nil, (char *)err.UTF8String);
  }
}

@implementation MacRPC
- (instancetype)init {
  self = [super init];
  self.handlers = [NSMutableDictionary dictionaryWithCapacity:64];
  return self;
}

- (void)handle:(NSString *)method withHandler:(MacRPCHandler)handler {
  self.handlers[method] = handler;
}

- (void) return:(NSString *)returnID
     withOutput:(NSDictionary *)out
       andError:(NSString *)err {

  char *creturnID = returnID != nil ? (char *)returnID.UTF8String : nil;
  char *cout =
      out != nil ? (char *)[JSONEncoder encodeObject:out].UTF8String : nil;
  char *cerr = err != nil ? (char *)err.UTF8String : nil;

  macCallReturn(creturnID, cout, cerr);
}
@end