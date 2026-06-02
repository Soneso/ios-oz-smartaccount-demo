// SignerManagementSection+Passkey.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerManagementSection: Passkey rows
// ============================================================================

extension SignerManagementSection {

    @ViewBuilder
    internal var passkeyContent: some View {
        passkeyHelperRow
        reuseSubsection
        Divider()
        registerSubsection
    }

    private var passkeyHelperRow: some View {
        Text(passkeyHelperText)
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
            .accessibilityHint("Passkey signer registration and reuse controls.")
    }

    private var passkeyHelperText: String {
        if isEditing {
            return "You can reuse a signer from any existing context rule, " +
                   "or register a new passkey signer for this context rule."
        }
        return "You can reuse an account signer that is already stored in an existing " +
               "context rule, or register a new passkey signer for this context rule."
    }

    @ViewBuilder
    private var reuseSubsection: some View {
        if isEditing {
            editReuseSubsection
        } else {
            reuseButton
            if passkeysLoaded {
                reuseResults
            }
        }
    }

    @ViewBuilder
    private var editReuseSubsection: some View {
        if !existingSigners.isEmpty {
            Text("Available signers from existing context rules:")
                .font(Typography.metadata)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            ForEach(
                Array(existingSigners.enumerated()),
                id: \.element.uniqueKey
            ) { _, signer in
                editReuseRow(for: signer)
            }
        }
    }

    private func editReuseRow(for passkey: any SmartAccountSignerProtocol) -> some View {
        let display = signerDisplayIdentifier(for: passkey)
        let alreadyAdded = signerEntries.contains {
            SmartAccountBuilders.signersEqual($0.signer, passkey)
        }
        return Button {
            addReusedPasskeyEdit(passkey, display: display)
        } label: {
            Text(alreadyAdded ? "\(display) (already added)" : "Add: \(display)")
                .font(Typography.metadata)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.reuseButtonVerticalPadding)
                .padding(.horizontal, Self.reuseButtonHorizontalPadding)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.reuseButtonRadius)
                        .stroke(Color.accentColor.opacity(Self.reuseButtonStrokeAlpha), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isSubmitting)
        .accessibilityLabel(alreadyAdded ? "\(display) already added" : "Add \(display)")
    }

    private func addReusedPasskeyEdit(
        _ passkey: any SmartAccountSignerProtocol,
        display: String
    ) {
        if let validationError = validateAddEdit(passkey) {
            fieldErrors["signers"] = validationError
            return
        }
        let entry = EditSignerEntry(signer: passkey, onChainId: nil, isOriginal: false)
        onAddEntry?(entry)
        fieldErrors.removeValue(forKey: "signers")
        let safe = ActivityLogState.redactCredentialId(display)
        activityLog.success("Added passkey signer: \(safe)")
    }

    private var reuseButton: some View {
        Button {
            Task { await loadPasskeys() }
        } label: {
            HStack(spacing: 6) {
                if isLoadingPasskeys {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }
                Text(isLoadingPasskeys ? "Loading..." : "Reuse Signer")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.addButtonVerticalPadding)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPasskeys || isRegistering || passkeysLoaded)
        .accessibilityLabel(isLoadingPasskeys ? "Loading passkeys" : "Reuse signer")
    }

    @ViewBuilder
    private var reuseResults: some View {
        if availablePasskeys.isEmpty {
            emptyReuseText
        } else {
            Text("Available signers from existing context rules:")
                .font(Typography.metadata)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            ForEach(
                Array(availablePasskeys.enumerated()),
                id: \.element.uniqueKey
            ) { _, passkey in
                reuseRow(for: passkey)
            }
        }
    }

    private var emptyReuseText: some View {
        ContentUnavailableView(
            "No Existing Passkey Signers",
            systemImage: "key.slash",
            description: Text("No passkey signers are registered on this account yet.")
        )
        .symbolRenderingMode(.hierarchical)
        .modifier(
            AccessibilityAnnouncementModifier(
                text: "No existing passkey signers found on this account."
            )
        )
    }

    private func reuseRow(for passkey: any SmartAccountSignerProtocol) -> some View {
        let display = signerDisplayIdentifier(for: passkey)
        let alreadyAdded = signers.contains { SmartAccountBuilders.signersEqual($0, passkey) }
        return Button {
            addReusedPasskey(passkey, display: display)
        } label: {
            Text(alreadyAdded ? "\(display) (already added)" : "Add: \(display)")
                .font(Typography.metadata)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.reuseButtonVerticalPadding)
                .padding(.horizontal, Self.reuseButtonHorizontalPadding)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.reuseButtonRadius)
                        .stroke(Color.accentColor.opacity(Self.reuseButtonStrokeAlpha), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isSubmitting)
        .accessibilityLabel(alreadyAdded ? "\(display) already added" : "Add \(display)")
    }

    private func addReusedPasskey(_ passkey: any SmartAccountSignerProtocol, display: String) {
        if let validationError = validateAdd(passkey) {
            fieldErrors["signers"] = validationError
            return
        }
        signers.append(passkey)
        fieldErrors.removeValue(forKey: "signers")
        let safe = ActivityLogState.redactCredentialId(display)
        activityLog.success("Added passkey signer: \(safe)")
    }

    @ViewBuilder
    internal var registerSubsection: some View {
        Text("Register a new passkey signer for this context rule:")
            .font(Typography.metadata)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        TextField("e.g., Recovery Key", text: $newPasskeyName)
            .font(Typography.mono)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityLabel("Passkey Name")
        registerButton
    }

    private var registerButton: some View {
        Button {
            Task { await registerPasskey() }
        } label: {
            HStack(spacing: 6) {
                if isRegistering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }
                Text(isRegistering ? "Registering..." : "Register New")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.addButtonVerticalPadding)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Self.addButtonRadius))
        }
        .buttonStyle(.plain)
        .disabled(registerDisabled)
        .accessibilityLabel(isRegistering ? "Registering passkey" : "Register new passkey")
    }

    private var registerDisabled: Bool {
        isRegistering ||
        isLoadingPasskeys ||
        isSubmitting ||
        newPasskeyName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Vertical padding inside the outlined "Add" reuse-passkey row button.
    fileprivate static var reuseButtonVerticalPadding: CGFloat { 8 }

    /// Horizontal padding inside the outlined "Add" reuse-passkey row button.
    fileprivate static var reuseButtonHorizontalPadding: CGFloat { 10 }

    /// Corner radius applied to the outlined "Add" reuse-passkey row button.
    fileprivate static var reuseButtonRadius: CGFloat { 8 }

    /// Stroke alpha applied to the outlined "Add" reuse-passkey row button.
    fileprivate static var reuseButtonStrokeAlpha: Double { 0.4 }

    @MainActor
    internal func loadPasskeys() async {
        isLoadingPasskeys = true
        defer { isLoadingPasskeys = false }
        let loaded = await flow.loadAvailablePasskeySigners(
            excludeCredentialId: connectedCredentialId
        )
        availablePasskeys = loaded
        passkeysLoaded = true
        if loaded.isEmpty {
            activityLog.info("No additional passkey signers found")
        }
    }

    @MainActor
    internal func registerPasskey() async {
        let name = newPasskeyName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return }
        isRegistering = true
        defer { isRegistering = false }
        do {
            let newSigner = try await flow.registerPasskeySigner(name: name)
            handleRegisteredSigner(newSigner)
        } catch {
            handleRegistrationError(error)
        }
    }

    private func handleRegisteredSigner(_ newSigner: any SmartAccountSignerProtocol) {
        if isEditing {
            if let validationError = validateAddEdit(newSigner) {
                fieldErrors["signers"] = validationError
                activityLog.info(validationError)
                return
            }
            let entry = EditSignerEntry(
                signer: newSigner, onChainId: nil, isOriginal: false, isPending: true
            )
            onAddEntry?(entry)
        } else {
            if let validationError = validateAdd(newSigner) {
                fieldErrors["signers"] = validationError
                activityLog.info(validationError)
                return
            }
            signers.append(newSigner)
        }
        availablePasskeys.append(newSigner)
        passkeysLoaded = true
        newPasskeyName = ""
        fieldErrors.removeValue(forKey: "signers")
        let display = signerDisplayIdentifier(for: newSigner)
        let safe = ActivityLogState.redactCredentialId(display)
        activityLog.success("Registered and added new passkey signer: \(safe)")
    }

    /// Edit-mode validator that consults `signerEntries` rather than `signers`
    /// because edit-mode appends go through the entry list.
    internal func validateAddEdit(_ candidate: any SmartAccountSignerProtocol) -> String? {
        if signerEntries.count >= OZSmartAccountConstants.maxSigners {
            return "Maximum \(OZSmartAccountConstants.maxSigners) signers allowed"
        }
        if signerEntries.contains(where: {
            SmartAccountBuilders.signersEqual($0.signer, candidate)
        }) {
            return "This signer is already added"
        }
        return nil
    }

    private func handleRegistrationError(_ error: Error) {
        if isUserCancellation(error) {
            activityLog.info("Passkey registration cancelled")
        } else {
            let detail = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Failed to register passkey: \(detail)")
        }
    }
}
