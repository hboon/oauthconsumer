//
//  OAMutableURLRequest.m
//  OAuthConsumer
//
//  Created by Jon Crosby on 10/19/07.
//  Copyright 2007 Kaboomerang LLC. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#import "OAMutableURLRequest.h"


@interface OAMutableURLRequest (Private)
- (void)_generateTimestamp;
- (void)_generateNonce;
- (NSString *)_signatureBaseString;
@end

@implementation OAMutableURLRequest
@synthesize nonce;
@synthesize token;
@synthesize realm;
@synthesize signatureProvider;
@synthesize timestamp;


- (void)dealloc {
	self.token = nil;
	self.realm = nil;
	self.signatureProvider = nil;
	self.timestamp = nil;
	[nonce release];

	[super dealloc];
}

#pragma mark init

- (id)initWithURL:(NSURL *)aUrl
		 consumer:(OAConsumer *)aConsumer
			token:(OAToken *)aToken
            realm:(NSString *)aRealm
signatureProvider:(id<OASignatureProviding, NSObject>)aProvider {
    [super initWithURL:aUrl
           cachePolicy:NSURLRequestReloadIgnoringCacheData
       timeoutInterval:10.0];
    
    consumer = aConsumer;
    
    // empty token for Unauthorized Request Token transaction
    if (aToken == nil) {
        self.token = [[[OAToken alloc] init] autorelease];
    } else {
        self.token = aToken;
    }
    
    if (aRealm == nil) {
        self.realm = @"";
    } else {
        self.realm = aRealm;
    }
      
    // default to HMAC-SHA1
    if (aProvider == nil) {
        self.signatureProvider = [[[OAHMAC_SHA1SignatureProvider alloc] init] autorelease];
    } else {
        self.signatureProvider = aProvider;
    }
    
    [self _generateTimestamp];
    [self _generateNonce];
    
    return self;
}

// Setting a timestamp and nonce to known
// values can be helpful for testing
- (id)initWithURL:(NSURL *)aUrl
		 consumer:(OAConsumer *)aConsumer
			token:(OAToken *)aToken
            realm:(NSString *)aRealm
signatureProvider:(id<OASignatureProviding, NSObject>)aProvider
            nonce:(NSString *)aNonce
        timestamp:(NSString *)aTimestamp {
    [self initWithURL:aUrl
             consumer:aConsumer
                token:aToken
                realm:aRealm
    signatureProvider:aProvider];
    
    nonce = [aNonce copy];
    self.timestamp = aTimestamp;
    
    return self;
}

- (void)prepare {
    // sign
//	NSLog(@"Base string is: %@", [self _signatureBaseString]);
   NSString* signature = [signatureProvider signClearText:[self _signatureBaseString]
                                      withSecret:[NSString stringWithFormat:@"%@&%@",
                                                  consumer.secret,
                                                  token.secret ? token.secret : @""]];
    
    // set OAuth headers
	NSMutableArray *chunks = [[NSMutableArray alloc] init];
	[chunks addObject:[NSString stringWithFormat:@"realm=\"%@\"", [realm encodedURLParameterString]]];
	[chunks addObject:[NSString stringWithFormat:@"oauth_consumer_key=\"%@\"", [consumer.key encodedURLParameterString]]];

	NSDictionary *tokenParameters = [token parameters];
	for (NSString *k in tokenParameters) {
		[chunks addObject:[NSString stringWithFormat:@"%@=\"%@\"", k, [[tokenParameters objectForKey:k] encodedURLParameterString]]];
	}

	[chunks addObject:[NSString stringWithFormat:@"oauth_signature_method=\"%@\"", [[signatureProvider name] encodedURLParameterString]]];
	[chunks addObject:[NSString stringWithFormat:@"oauth_signature=\"%@\"", [signature encodedURLParameterString]]];
	[chunks addObject:[NSString stringWithFormat:@"oauth_timestamp=\"%@\"", timestamp]];
	[chunks addObject:[NSString stringWithFormat:@"oauth_nonce=\"%@\"", nonce]];
	[chunks	addObject:@"oauth_version=\"1.0\""];
	
	NSString *oauthHeader = [NSString stringWithFormat:@"OAuth %@", [chunks componentsJoinedByString:@", "]];
	[chunks release];

    [self setValue:oauthHeader forHTTPHeaderField:@"Authorization"];
}

- (void)_generateTimestamp {
    self.timestamp = [NSString stringWithFormat:@"%d", time(NULL)]; 
}

- (void)_generateNonce {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    NSMakeCollectable(theUUID);
    nonce = [(NSString *)string copy];
}

- (NSString *)_signatureBaseString {
    // OAuth Spec, Section 9.1.1 "Normalize Request Parameters"
    // build a sorted array of both request parameters and OAuth header parameters
	NSDictionary *tokenParameters = [token parameters];
	// 6 being the number of OAuth params in the Signature Base String
	NSMutableArray *parameterPairs = [[NSMutableArray alloc] initWithCapacity:(5 + [[self parameters] count] + [tokenParameters count])];
    
    [parameterPairs addObject:[[[OARequestParameter alloc] initWithName:@"oauth_consumer_key" value:consumer.key] URLEncodedNameValuePair]];
    [parameterPairs addObject:[[[OARequestParameter alloc] initWithName:@"oauth_signature_method" value:[signatureProvider name]] URLEncodedNameValuePair]];
    [parameterPairs addObject:[[[OARequestParameter alloc] initWithName:@"oauth_timestamp" value:timestamp] URLEncodedNameValuePair]];
    [parameterPairs addObject:[[[OARequestParameter alloc] initWithName:@"oauth_nonce" value:nonce] URLEncodedNameValuePair]];
    [parameterPairs addObject:[[[OARequestParameter alloc] initWithName:@"oauth_version" value:@"1.0"] URLEncodedNameValuePair]];
	

	for(NSString *k in tokenParameters) {
		[parameterPairs addObject:[[OARequestParameter requestParameter:k value:[tokenParameters objectForKey:k]] URLEncodedNameValuePair]];
	}
    
	if (![[self valueForHTTPHeaderField:@"Content-Type"] hasPrefix:@"multipart/form-data"]) {
		for (OARequestParameter *param in [self parameters]) {
			[parameterPairs addObject:[param URLEncodedNameValuePair]];
		}
	}
    
    NSArray *sortedPairs = [parameterPairs sortedArrayUsingSelector:@selector(compare:)];
    NSString *normalizedRequestParameters = [sortedPairs componentsJoinedByString:@"&"];
    
//	NSLog(@"Normalized: %@", normalizedRequestParameters);
    // OAuth Spec, Section 9.1.2 "Concatenate Request Elements"
    return [NSString stringWithFormat:@"%@&%@&%@",
            [self HTTPMethod],
            [[[self URL] URLStringWithoutQuery] encodedURLParameterString],
            [normalizedRequestParameters encodedURLString]];
}

@end
