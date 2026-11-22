//
//  OIDCWebSignInTests.swift
//  SpoolKidTests
//
//  Purpose: The system sign-in sheet's errors map to OIDCError, and backing
//  out of the sheet is silent.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AuthenticationServices
import Testing
@testable import SpoolKid

@Suite("OIDCWebSignIn")
struct OIDCWebSignInTests {
    @Test func cancelIsSilent() {
        let error = OIDCWebSignIn.mapError(ASWebAuthenticationSessionError(.canceledLogin))
        #expect(error == .cancelled)
        #expect(OIDCError.cancelled.message == "")
    }

    @Test func otherErrorsAreProviderErrors() {
        let error = OIDCWebSignIn.mapError(ASWebAuthenticationSessionError(.presentationContextNotProvided))
        guard case .providerError = error else {
            Issue.record("expected providerError, got \(error)")
            return
        }
    }
}
