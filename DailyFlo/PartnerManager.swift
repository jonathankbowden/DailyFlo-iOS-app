//
//  PartnerManager.swift
//  DailyFlo
//
//  Owns the partner-share data path: invitations today, relationships next.
//
//  Day 8 of the 30-for-30 (Sept 2026): "Send Invite" now writes a real row to
//  the `invitations` table instead of showing a random local number. The code
//  is generated client-side, is unique per the table's UNIQUE constraint, and
//  expires 30 days after creation.
//  Day 9: the code goes out through the system share sheet as a ready-to-send
//  message (`PartnerInvitation.shareMessage`). Accepting a code, reading the
//  connected state, and permissions arrive on the following days.
//

import Foundation
import Supabase

// MARK: - Model

/// A partner invitation the signed-in tracker has sent. Mirrors the columns
/// of `invitations` that the client needs; the DB row is the source of truth.
struct PartnerInvitation: Identifiable, Equatable {
    let id: UUID
    let code: String
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }

    /// The text handed to the share sheet. Plain text travels everywhere
    /// (Messages, Mail, WhatsApp, Notes) and the code is easy to type or copy
    /// on the other end. Written in the tracker's voice since it goes out
    /// from their phone; `senderName` becomes a sign-off, or nothing when we
    /// only have the placeholder name.
    func shareMessage(senderName: String) -> String {
        let name = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiry = expiresAt.formatted(date: .abbreviated, time: .omitted)
        let signOff = name.isEmpty ? "" : "\n\n— \(name)"

        return """
        I'd love for you to join me on DailyFLO so you can understand my cycle and support me through each phase.

        Get the DailyFLO app, tap Connect, and enter my invite code:

        \(code)

        The code works until \(expiry).\(signOff)
        """
    }
}

// MARK: - Manager

@Observable
final class PartnerManager {
    static let shared = PartnerManager()

    /// The tracker's newest invitation that is neither accepted nor expired.
    /// `nil` until `refresh()` has run, or when there is nothing outstanding.
    private(set) var pendingInvitation: PartnerInvitation?

    /// True while a network read or write is in flight.
    private(set) var isLoading = false

    private let invitationsTable = "invitations"

    /// Invitations stay valid for this long; matches the schema default.
    static let invitationLifetimeDays = 30

    /// The relationship the "Invite Your Partner" screen proposes. Parent and
    /// teen pairs get their own entry point in v1.x.
    static let defaultRelationshipType = "partner"

    /// Permissions granted the moment a supporter accepts. Mirrors the default
    /// shape documented for `partner_relationships.permissions`.
    static let defaultPermissions: [String: Bool] = [
        "show_current_phase": true,
        "show_phase_predictions": true,
        "show_period_dates": true,
        "show_journal_summary": false,
        "show_journal_full": false,
        "show_basal_temp": false,
        "notify_on_phase_change": true,
        "notify_on_period_start": true,
        "notify_on_journal_entry": false
    ]

    private init() {}

    // MARK: - Reads

    /// Loads the newest open invitation for the signed-in user into
    /// `pendingInvitation`. Signed-out users simply see `nil`.
    @MainActor
    func refresh() async {
        guard let userId = currentUserId() else {
            pendingInvitation = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [InvitationRow] = try await SupabaseClient.shared
                .from(invitationsTable)
                .select(InvitationRow.columns)
                .eq("tracker_user_id", value: userId)
                .is("accepted_at", value: nil)
                .gt("expires_at", value: Self.timestampFormatter.string(from: Date()))
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            pendingInvitation = rows.first.flatMap(PartnerInvitation.init(row:))
            #if DEBUG
            print("[PartnerManager] refresh OK — pending invitation: \(pendingInvitation?.code ?? "none")")
            #endif
        } catch {
            logRemoteError(operation: "refresh", error: error)
        }
    }

    // MARK: - Writes

    /// Returns the open invitation to share, creating one only when none
    /// exists. Reopening the invite sheet therefore never mints a second code.
    @MainActor
    func ensurePendingInvitation() async throws -> PartnerInvitation {
        if let existing = pendingInvitation, !existing.isExpired {
            return existing
        }

        guard let userId = currentUserId() else {
            throw PartnerError.notSignedIn
        }

        isLoading = true
        defer { isLoading = false }

        let invitation = try await createInvitation(userId: userId)
        pendingInvitation = invitation
        return invitation
    }

    /// Inserts a new `invitations` row. The code is random, so on the rare
    /// UNIQUE collision (Postgres 23505) a fresh code is tried, up to three
    /// times, before the error surfaces.
    private func createInvitation(userId: UUID) async throws -> PartnerInvitation {
        let expiresAt = Calendar.current.date(
            byAdding: .day,
            value: Self.invitationLifetimeDays,
            to: Date()
        ) ?? Date()

        var lastError: Error?
        for attempt in 1...3 {
            let row = InvitationInsertRow(
                trackerUserId: userId,
                invitationCode: Self.generateCode(),
                relationshipType: Self.defaultRelationshipType,
                proposedPermissions: Self.defaultPermissions,
                expiresAt: Self.timestampFormatter.string(from: expiresAt)
            )

            do {
                let inserted: InvitationRow = try await SupabaseClient.shared
                    .from(invitationsTable)
                    .insert(row)
                    .select(InvitationRow.columns)
                    .single()
                    .execute()
                    .value

                guard let invitation = PartnerInvitation(row: inserted) else {
                    throw PartnerError.malformedRow
                }
                #if DEBUG
                print("[PartnerManager] invitation insert OK — code \(invitation.code) for user \(userId)")
                #endif
                return invitation
            } catch let error as PostgrestError where error.code == "23505" {
                // Code already taken; loop and try another.
                lastError = error
                #if DEBUG
                print("[PartnerManager] invitation code collision on attempt \(attempt), retrying")
                #endif
            } catch {
                logRemoteError(operation: "invitation insert", error: error)
                throw error
            }
        }

        logRemoteError(operation: "invitation insert", error: lastError ?? PartnerError.codeCollision)
        throw lastError ?? PartnerError.codeCollision
    }

    // MARK: - Codes

    /// Characters that survive being read aloud or typed from a text message:
    /// no 0/O, no 1/I/L. Six of them give ~1.07 billion combinations.
    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let codeLength = 6

    /// Produces a user-facing code such as `FLO-A3K2M7`.
    static func generateCode() -> String {
        let body = String((0..<codeLength).map { _ in codeAlphabet.randomElement()! })
        return "FLO-\(body)"
    }

    // MARK: - Helpers

    private func currentUserId() -> UUID? {
        SupabaseClient.shared.auth.currentSession?.user.id
    }

    /// ISO 8601 with fractional seconds; what `timestamptz` columns return.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres emits up to six fractional digits; Foundation's parser only
    /// promises three. Trim before parsing so neither form is rejected.
    static func parseTimestamp(_ raw: String) -> Date? {
        if let date = plainTimestampFormatter.date(from: raw) { return date }
        if let date = timestampFormatter.date(from: raw) { return date }

        guard let dot = raw.firstIndex(of: "."),
              let zoneStart = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        else { return nil }

        let fraction = raw[raw.index(after: dot)..<zoneStart].prefix(3)
        let padded = fraction + String(repeating: "0", count: max(0, 3 - fraction.count))
        let normalized = raw[..<dot] + "." + padded + raw[zoneStart...]
        return timestampFormatter.date(from: String(normalized))
    }

    private func logRemoteError(operation: String, error: Error) {
        #if DEBUG
        if let pg = error as? PostgrestError {
            print("[PartnerManager] \(operation) failed — PostgrestError code=\(pg.code ?? "nil") message=\"\(pg.message)\" detail=\(pg.detail ?? "nil") hint=\(pg.hint ?? "nil")")
        } else if let http = error as? HTTPError {
            let body = String(data: http.data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[PartnerManager] \(operation) failed — HTTP \(http.response.statusCode): \(body)")
        } else {
            print("[PartnerManager] \(operation) failed — \(type(of: error)): \(error.localizedDescription)")
        }
        #endif
    }
}

// MARK: - Errors

enum PartnerError: LocalizedError {
    case notSignedIn
    case malformedRow
    case codeCollision

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to invite a partner."
        case .malformedRow: return "The invitation came back incomplete. Please try again."
        case .codeCollision: return "Couldn't create a unique code. Please try again."
        }
    }
}

// MARK: - DB row representations

private struct InvitationInsertRow: Encodable {
    let trackerUserId: UUID
    let invitationCode: String
    let relationshipType: String
    let proposedPermissions: [String: Bool]
    let expiresAt: String  // ISO 8601 timestamp

    enum CodingKeys: String, CodingKey {
        case trackerUserId = "tracker_user_id"
        case invitationCode = "invitation_code"
        case relationshipType = "relationship_type"
        case proposedPermissions = "proposed_permissions"
        case expiresAt = "expires_at"
    }
}

private struct InvitationRow: Decodable {
    static let columns = "id, invitation_code, created_at, expires_at, accepted_at"

    let id: UUID
    let invitationCode: String
    let createdAt: String
    let expiresAt: String
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case invitationCode = "invitation_code"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
    }
}

private extension PartnerInvitation {
    init?(row: InvitationRow) {
        guard let created = PartnerManager.parseTimestamp(row.createdAt),
              let expires = PartnerManager.parseTimestamp(row.expiresAt)
        else { return nil }
        self.init(id: row.id, code: row.invitationCode, createdAt: created, expiresAt: expires)
    }
}
