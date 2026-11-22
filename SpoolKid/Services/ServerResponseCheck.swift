//
//  ServerResponseCheck.swift
//  SpoolKid
//
//  Purpose: Tells a web page from the API's data. Spoolman and FilaMan answer
//  every path outside their API with their web UI, or with a sign-in page when
//  a proxy sits in front, as 200 text/html. Left alone that reads as a JSON
//  decoding error, a green connection dot or a tag link that "succeeded" without
//  writing anything, so every transport site turns it into one error.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ServerResponseCheck {
    /// The MIME essence: parameters (`; charset=…`) and case do not matter.
    static func isWebPage(mimeType: String?) -> Bool {
        guard let essence = mimeType?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        else { return false }
        return essence == "text/html" || essence == "application/xhtml+xml"
    }

    /// Only the statuses where the caller expects the API's data (2xx) or its
    /// sign-in verdict (401, 403). An HTML body on a 404 or 5xx is an ordinary
    /// error answer, which `errorText` and `extractErrorMessage` keep out of
    /// the message instead.
    static func isWebPageInsteadOfData(statusCode: Int, mimeType: String?) -> Bool {
        guard isWebPage(mimeType: mimeType) else { return false }
        return (200...299).contains(statusCode) || statusCode == 401 || statusCode == 403
    }

    /// A 401 or 403 answered with a page, as nginx `auth_basic` does in front of
    /// Spoolman. Spoolman has Basic Auth settings to point at; FilaMan has none,
    /// so its caller keeps `webPageMessage`.
    static func signInPageMessage(backendName: String, statusCode: Int) -> String {
        "The server answered with a sign-in page (HTTP \(statusCode)). "
            + "If a user name and password protect \(backendName), check them under Authentication."
    }

    static func webPageMessage(backendName: String) -> String {
        "The server sent a web page instead of \(backendName) data. "
            + "Check that the address is your \(backendName) server, not a page inside it, "
            + "and that no sign-in page sits in front of its API."
    }
}
