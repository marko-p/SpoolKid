//
//  OIDCWebSignIn.swift
//  SpoolKid
//
//  Purpose: Presents the provider's sign-in page in the system's web
//  authentication sheet and hands back the callback URL. The sheet shares
//  Safari's cookies, so an existing provider session signs in without typing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AuthenticationServices
import UIKit

@MainActor
enum OIDCWebSignIn {
    /// Shows `url` and returns the URL the provider redirected to.
    static func present(_ url: URL) async throws(OIDCError) -> URL {
        let anchor = PresentationAnchor()
        // The session must stay referenced until it completes; a session
        // nobody holds can be torn down without ever calling back.
        let holder = SessionHolder()
        let result: Result<URL, OIDCError> = await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(OIDCConfiguration.callbackScheme)
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: .success(callbackURL))
                } else {
                    continuation.resume(returning: .failure(mapError(error ?? OIDCError.cancelled)))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = anchor
            holder.session = session
            if !session.start() {
                continuation.resume(returning: .failure(.providerError("The sign-in page could not be shown.")))
            }
        }
        withExtendedLifetime((anchor, holder)) {}
        return try result.get()
    }

    private final class SessionHolder {
        var session: ASWebAuthenticationSession?
    }

    nonisolated static func mapError(_ error: Error) -> OIDCError {
        if let oidc = error as? OIDCError { return oidc }
        if let web = error as? ASWebAuthenticationSessionError, web.code == .canceledLogin {
            return .cancelled
        }
        return .providerError(error.localizedDescription)
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
