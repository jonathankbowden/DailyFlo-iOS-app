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
//  message (`PartnerInvitation.shareMessage`).
//  Day 10: a supporter accepts a code through the `accept_invitation` RPC
//  (supabase/migrations/20260910_accept_invitation.sql), which creates the
//  `partner_relationships` row server-side.
//  Day 11: `refresh()` loads the active relationship through the
//  `my_partner_relationships` RPC, so Connect shows real state on launch on
//  both phones.
//  Day 12: the supporter home renders from `SupporterSnapshot`, loaded
//  through the permission-gated `supporter_snapshot` RPC.
//  Day 13: the tracker toggles phase sharing (`update_partner_permissions`)
//  and either side can disconnect (`disconnect_partner`, a soft end via
//  `ended_at`). Permission keys are settled on the `show_*` / `notify_*`
//  names below; the RLS gate aliases the older `view_*` spellings.
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

/// The relationship a supporter just joined by accepting a code. Mirrors the
/// `partner_relationships` row the RPC returns, plus the tracker's name.
struct PartnerConnection: Identifiable, Equatable {
    let id: UUID
    let trackerUserId: UUID
    /// The tracker's chosen display name; "" when they haven't set one.
    let trackerDisplayName: String
    let relationshipType: String
    let status: String
    let permissions: [String: Bool]
    let acceptedAt: Date
}

/// An active `partner_relationships` row as seen from either side, with both
/// display names attached. The source of truth for "connected".
struct PartnerRelationship: Identifiable, Equatable {
    let id: UUID
    let trackerUserId: UUID
    let supporterUserId: UUID
    /// "" when that person hasn't set a name yet.
    let trackerDisplayName: String
    let supporterDisplayName: String
    let relationshipType: String
    let status: String
    let permissions: [String: Bool]
    let acceptedAt: Date?

    /// True when `userId` is the person sharing their cycle.
    func isTracker(_ userId: UUID?) -> Bool {
        userId == trackerUserId
    }

    /// The other party's display name from `userId`'s point of view.
    func partnerDisplayName(viewedBy userId: UUID?) -> String {
        isTracker(userId) ? supporterDisplayName : trackerDisplayName
    }

    /// Whether the supporter may see the tracker's current phase. Missing
    /// key reads as off; the server gates on the same key.
    var sharesCurrentPhase: Bool {
        permissions[PartnerManager.currentPhasePermissionKey] ?? false
    }
}

/// What the supporter home renders: who they support and, when permitted,
/// the inputs for that person's current phase. Cycle fields are `nil` when
/// the tracker hasn't shared their phase or hasn't logged a period yet.
struct SupporterSnapshot: Equatable {
    let relationshipId: UUID
    let trackerUserId: UUID
    /// "" when the tracker hasn't set a name yet.
    let trackerDisplayName: String
    let canViewPhase: Bool
    let lastPeriodStart: Date?
    let cycleLengthDays: Int?
    let periodLengthDays: Int?

    /// True when the phase can be computed: permission granted and a
    /// period has been logged.
    var hasPhaseData: Bool {
        canViewPhase && lastPeriodStart != nil
    }

    /// The tracker's cycle day today, using the same math as their own app.
    var currentCycleDay: Int? {
        guard let start = lastPeriodStart, let length = cycleLengthDays else { return nil }
        return CycleManager.dayOfCycle(on: Date(), lastPeriodStart: start, cycleLength: length)
    }

    var currentPhase: CyclePhase? {
        guard let day = currentCycleDay, let length = cycleLengthDays, let period = periodLengthDays else { return nil }
        return CycleManager.phase(forCycleDay: day, cycleLength: length, periodLength: period)
    }
}

// MARK: - Manager

@Observable
final class PartnerManager {
    static let shared = PartnerManager()

    /// The tracker's newest invitation that is neither accepted nor expired.
    /// `nil` until `refresh()` has run, or when there is nothing outstanding.
    private(set) var pendingInvitation: PartnerInvitation?

    /// The signed-in user's active relationship, from either side. `nil`
    /// until `refresh()` has run, or when there is none. v1 supports one
    /// partner; the newest active row wins if more ever exist.
    private(set) var activeRelationship: PartnerRelationship?

    /// True while a network read or write is in flight.
    private(set) var isLoading = false

    private let invitationsTable = "invitations"
    private let acceptInvitationFunction = "accept_invitation"
    private let relationshipsFunction = "my_partner_relationships"
    private let supporterSnapshotFunction = "supporter_snapshot"
    private let updatePermissionsFunction = "update_partner_permissions"
    private let disconnectFunction = "disconnect_partner"

    /// The one permission v1 exposes as a switch. The other keys in
    /// `defaultPermissions` stay stored for features that don't exist yet.
    static let currentPhasePermissionKey = "show_current_phase"

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

    /// Loads what Connect needs to pick a state: the active relationship
    /// (either side) and, for trackers, the newest open invitation.
    /// Signed-out users simply see `nil` for both.
    @MainActor
    func refresh() async {
        guard let userId = currentUserId() else {
            activeRelationship = nil
            pendingInvitation = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        await loadActiveRelationship()
        await loadPendingInvitation(userId: userId)
    }

    /// Reads the active relationship through the RPC. Both parties can call
    /// it; the server decides which rows are theirs.
    @MainActor
    func loadActiveRelationship() async {
        do {
            let rows: [RelationshipRow] = try await SupabaseClient.shared
                .rpc(relationshipsFunction)
                .execute()
                .value

            activeRelationship = rows.first.flatMap(PartnerRelationship.init(row:))
            #if DEBUG
            print("[PartnerManager] relationships OK — active: \(activeRelationship?.id.uuidString ?? "none")")
            #endif
        } catch {
            logRemoteError(operation: "relationships fetch", error: error)
        }
    }

    /// Loads the supporter home's data. Returns `nil` when the signed-in
    /// user isn't a supporter in any active relationship. Throws on network
    /// or decode failure so the screen can show a retry.
    @MainActor
    func loadSupporterSnapshot() async throws -> SupporterSnapshot? {
        guard currentUserId() != nil else { return nil }

        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [SupporterSnapshotRow] = try await SupabaseClient.shared
                .rpc(supporterSnapshotFunction)
                .execute()
                .value

            let snapshot = rows.first.map(SupporterSnapshot.init(row:))
            #if DEBUG
            print("[PartnerManager] supporter snapshot OK — tracker: \(snapshot?.trackerDisplayName ?? "none"), phase visible: \(snapshot?.canViewPhase ?? false)")
            #endif
            return snapshot
        } catch {
            logRemoteError(operation: "supporter snapshot", error: error)
            throw error
        }
    }

    @MainActor
    private func loadPendingInvitation(userId: UUID) async {
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

    /// Accepts a code the supporter typed. The server owns every rule
    /// (lookup, expiry, single use, not your own code) and performs the
    /// relationship insert atomically; this just calls it and maps the
    /// outcome. Success also settles `profiles.role` server-side, so the
    /// caller should refresh `CycleManager` when it's ready to re-route.
    @MainActor
    func acceptInvitation(code rawCode: String) async throws -> PartnerConnection {
        guard currentUserId() != nil else {
            throw PartnerError.notSignedIn
        }

        let code = Self.normalizeCode(rawCode)
        guard code.count == "FLO-".count + Self.codeLength else {
            throw PartnerError.malformedCode
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let row: AcceptInvitationRow = try await SupabaseClient.shared
                .rpc(acceptInvitationFunction, params: ["p_code": code])
                .single()
                .execute()
                .value

            guard let connection = PartnerConnection(row: row) else {
                throw PartnerError.malformedRow
            }
            #if DEBUG
            print("[PartnerManager] accept OK — relationship \(connection.id) with tracker \(connection.trackerUserId)")
            #endif
            // The row now exists; read it back so Connect renders from the
            // same source it uses on launch.
            await loadActiveRelationship()
            return connection
        } catch let error as PostgrestError {
            logRemoteError(operation: "accept invitation", error: error)
            if let mapped = PartnerError(rpcMessage: error.message) {
                throw mapped
            }
            throw error
        } catch {
            logRemoteError(operation: "accept invitation", error: error)
            throw error
        }
    }

    /// Tracker turns phase sharing on or off. The server merges the key into
    /// the stored JSON and the relationship is re-read so the card and the
    /// supporter's next refresh agree.
    @MainActor
    func setSharesCurrentPhase(_ enabled: Bool, for relationship: PartnerRelationship) async throws {
        guard currentUserId() != nil else { throw PartnerError.notSignedIn }

        isLoading = true
        defer { isLoading = false }

        do {
            let params = UpdatePermissionsParams(
                relationshipId: relationship.id,
                permissions: [Self.currentPhasePermissionKey: enabled]
            )
            _ = try await SupabaseClient.shared
                .rpc(updatePermissionsFunction, params: params)
                .execute()
            #if DEBUG
            print("[PartnerManager] permissions update OK — \(Self.currentPhasePermissionKey)=\(enabled)")
            #endif
        } catch let error as PostgrestError {
            logRemoteError(operation: "permissions update", error: error)
            if let mapped = PartnerError(rpcMessage: error.message) { throw mapped }
            throw error
        } catch {
            logRemoteError(operation: "permissions update", error: error)
            throw error
        }

        await loadActiveRelationship()
    }

    /// Ends the relationship from either side. A soft end: the row stays for
    /// history, `ended_at` is set, and both parties' screens drop it on
    /// their next refresh.
    @MainActor
    func disconnect(_ relationship: PartnerRelationship) async throws {
        guard currentUserId() != nil else { throw PartnerError.notSignedIn }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await SupabaseClient.shared
                .rpc(disconnectFunction, params: ["p_relationship_id": relationship.id])
                .execute()
            #if DEBUG
            print("[PartnerManager] disconnect OK — relationship \(relationship.id)")
            #endif
        } catch let error as PostgrestError {
            logRemoteError(operation: "disconnect", error: error)
            if let mapped = PartnerError(rpcMessage: error.message) { throw mapped }
            throw error
        } catch {
            logRemoteError(operation: "disconnect", error: error)
            throw error
        }

        await refresh()
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

    /// Turns whatever a person typed or pasted (" flo a3k2m7 ", "A3K2-M7")
    /// into canonical `FLO-XXXXXX` form. The server normalizes too; doing it
    /// here gives instant feedback and keeps the pasted message text out of
    /// the request.
    static func normalizeCode(_ raw: String) -> String {
        var body = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        if body.hasPrefix("FLO") {
            body.removeFirst(3)
        }
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

    /// Postgres `date` columns arrive as "yyyy-MM-dd"; parsed in the
    /// device's calendar so cycle-day math lines up with local midnight.
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        dateOnlyFormatter.date(from: raw)
    }

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

enum PartnerError: LocalizedError, Equatable {
    case notSignedIn
    case malformedRow
    case codeCollision
    case malformedCode
    case invitationNotFound
    case invitationExpired
    case invitationAlreadyAccepted
    case ownInvitation
    case relationshipNotFound

    /// Maps the exact messages the partner RPCs raise to cases. Returns
    /// `nil` for anything else so unexpected failures surface unchanged.
    init?(rpcMessage: String) {
        switch rpcMessage.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "not_authenticated": self = .notSignedIn
        case "invitation_not_found": self = .invitationNotFound
        case "invitation_expired": self = .invitationExpired
        case "invitation_already_accepted": self = .invitationAlreadyAccepted
        case "own_invitation": self = .ownInvitation
        case "relationship_not_found": self = .relationshipNotFound
        default: return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to connect with a partner."
        case .malformedRow: return "The invitation came back incomplete. Please try again."
        case .codeCollision: return "Couldn't create a unique code. Please try again."
        case .malformedCode: return "Codes look like FLO-A3K2M7. Check the message you were sent."
        case .invitationNotFound: return "We couldn't find that code. Check it and try again."
        case .invitationExpired: return "That code has expired. Ask your partner to send a new one."
        case .invitationAlreadyAccepted: return "That code has already been used."
        case .ownInvitation: return "That's your own code — share it with your partner instead."
        case .relationshipNotFound: return "This connection has already ended. Pull down to refresh."
        }
    }
}

// MARK: - DB row representations

private struct UpdatePermissionsParams: Encodable {
    let relationshipId: UUID
    let permissions: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case relationshipId = "p_relationship_id"
        case permissions = "p_permissions"
    }
}

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

/// One row of the `supporter_snapshot` RPC's result set.
private struct SupporterSnapshotRow: Decodable {
    let relationshipId: UUID
    let trackerUserId: UUID
    let trackerDisplayName: String?
    let canViewPhase: Bool
    let lastPeriodStart: String?   // "yyyy-MM-dd"
    let cycleLengthDays: Int?
    let periodLengthDays: Int?

    enum CodingKeys: String, CodingKey {
        case relationshipId = "relationship_id"
        case trackerUserId = "tracker_user_id"
        case trackerDisplayName = "tracker_display_name"
        case canViewPhase = "can_view_phase"
        case lastPeriodStart = "last_period_start"
        case cycleLengthDays = "cycle_length_days"
        case periodLengthDays = "period_length_days"
    }
}

private extension SupporterSnapshot {
    init(row: SupporterSnapshotRow) {
        self.init(
            relationshipId: row.relationshipId,
            trackerUserId: row.trackerUserId,
            trackerDisplayName: row.trackerDisplayName ?? "",
            canViewPhase: row.canViewPhase,
            lastPeriodStart: row.lastPeriodStart.flatMap(PartnerManager.parseDate),
            cycleLengthDays: row.cycleLengthDays,
            periodLengthDays: row.periodLengthDays
        )
    }
}

/// One row of the `my_partner_relationships` RPC's result set.
private struct RelationshipRow: Decodable {
    let relationshipId: UUID
    let trackerUserId: UUID
    let supporterUserId: UUID
    let trackerDisplayName: String?
    let supporterDisplayName: String?
    let relationshipType: String
    let status: String
    let permissions: [String: Bool]?
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case relationshipId = "relationship_id"
        case trackerUserId = "tracker_user_id"
        case supporterUserId = "supporter_user_id"
        case trackerDisplayName = "tracker_display_name"
        case supporterDisplayName = "supporter_display_name"
        case relationshipType = "relationship_type"
        case status
        case permissions
        case acceptedAt = "accepted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relationshipId = try c.decode(UUID.self, forKey: .relationshipId)
        trackerUserId = try c.decode(UUID.self, forKey: .trackerUserId)
        supporterUserId = try c.decode(UUID.self, forKey: .supporterUserId)
        trackerDisplayName = try c.decodeIfPresent(String.self, forKey: .trackerDisplayName)
        supporterDisplayName = try c.decodeIfPresent(String.self, forKey: .supporterDisplayName)
        relationshipType = try c.decode(String.self, forKey: .relationshipType)
        status = try c.decode(String.self, forKey: .status)
        acceptedAt = try c.decodeIfPresent(String.self, forKey: .acceptedAt)
        // Tolerant on purpose; Day 13 owns the permissions model.
        permissions = try? c.decodeIfPresent([String: Bool].self, forKey: .permissions)
    }
}

private extension PartnerRelationship {
    init?(row: RelationshipRow) {
        self.init(
            id: row.relationshipId,
            trackerUserId: row.trackerUserId,
            supporterUserId: row.supporterUserId,
            trackerDisplayName: row.trackerDisplayName ?? "",
            supporterDisplayName: row.supporterDisplayName ?? "",
            relationshipType: row.relationshipType,
            status: row.status,
            permissions: row.permissions ?? [:],
            acceptedAt: row.acceptedAt.flatMap(PartnerManager.parseTimestamp)
        )
    }
}

/// One row of the `accept_invitation` RPC's result set.
private struct AcceptInvitationRow: Decodable {
    let relationshipId: UUID
    let trackerUserId: UUID
    let trackerDisplayName: String?
    let relationshipType: String
    let status: String
    let permissions: [String: Bool]?
    let acceptedAt: String

    enum CodingKeys: String, CodingKey {
        case relationshipId = "relationship_id"
        case trackerUserId = "tracker_user_id"
        case trackerDisplayName = "tracker_display_name"
        case relationshipType = "relationship_type"
        case status
        case permissions
        case acceptedAt = "accepted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relationshipId = try c.decode(UUID.self, forKey: .relationshipId)
        trackerUserId = try c.decode(UUID.self, forKey: .trackerUserId)
        trackerDisplayName = try c.decodeIfPresent(String.self, forKey: .trackerDisplayName)
        relationshipType = try c.decode(String.self, forKey: .relationshipType)
        status = try c.decode(String.self, forKey: .status)
        acceptedAt = try c.decode(String.self, forKey: .acceptedAt)
        // The relationship is already created by the time this decodes; a
        // permissions blob with an unexpected value type must not turn a
        // successful accept into an error. Day 13 owns the permissions model.
        permissions = try? c.decodeIfPresent([String: Bool].self, forKey: .permissions)
    }
}

private extension PartnerConnection {
    init?(row: AcceptInvitationRow) {
        guard let accepted = PartnerManager.parseTimestamp(row.acceptedAt) else { return nil }
        self.init(
            id: row.relationshipId,
            trackerUserId: row.trackerUserId,
            trackerDisplayName: row.trackerDisplayName ?? "",
            relationshipType: row.relationshipType,
            status: row.status,
            permissions: row.permissions ?? [:],
            acceptedAt: accepted
        )
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
