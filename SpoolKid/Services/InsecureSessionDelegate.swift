//
//  InsecureSessionDelegate.swift
//  SpoolKid
//
//  Purpose: A URLSessionDelegate that accepts any server certificate,
//  including self-signed certificates. Used when the "Trust All Certificates"
//  setting is enabled for users running Spoolman over HTTPS with self-signed certs.
//
//  Security note: This bypasses TLS certificate validation entirely.
//  It should only be used on trusted local networks.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
