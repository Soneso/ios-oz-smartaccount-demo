// DemoFlowFactory.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - DemoFlowFactory
// ============================================================================

/// Single construction site for all flow objects that depend on an
/// `OZSmartAccountKit` instance.
///
/// Every `Adapter(kit:)` call in the demo lives here. Components call a factory
/// method (passing `demoState` and `activityLog`) and receive a fully-wired
/// flow; they do not reach into `demoState.kit` or construct adapters directly.
///
/// `DemoFlowFactory` is a pure namespace (non-instantiatable enum). All methods
/// are `@MainActor` because they read `demoState.kit` — a `@Published` property
/// on a `@MainActor`-isolated `DemoState`.
public enum DemoFlowFactory {

    // -------------------------------------------------------------------------
    // MARK: - ContextRuleFlow (listing / read-only)
    // -------------------------------------------------------------------------

    /// Creates a `ContextRuleFlow` wired for the listing screen.
    ///
    /// Does not attach a smart-account executor, ledger source, or WebAuthn
    /// provider — the listing screen only calls `listContextRules()` and
    /// `removeContextRule()`.
    @MainActor
    public static func makeContextRuleListFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> ContextRuleFlow {
        let manager = demoState.kit.map {
            ContextRuleManagerFullAdapter(kit: $0)
        }
        return ContextRuleFlow(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: manager
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - ContextRuleFlow (builder / full)
    // -------------------------------------------------------------------------

    /// Creates a fully-wired `ContextRuleFlow` for the context-rule builder screen.
    ///
    /// Attaches a `SmartAccountExecutorAdapter`, `SorobanLatestLedgerSource`, and
    /// the WebAuthn provider from `demoState`, allowing the builder to submit
    /// create/edit transactions.
    @MainActor
    public static func makeContextRuleBuilderFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> ContextRuleFlow {
        let manager = demoState.kit.map {
            ContextRuleManagerFullAdapter(kit: $0)
        }
        let executor: (any SmartAccountExecutorType)? = demoState.kit.map { kit in
            SmartAccountExecutorAdapter(
                transactionOperations: kit.transactionOperations,
                multiSignerManager: kit.multiSignerManager
            )
        }
        let ledger: (any LatestLedgerSource)? = demoState.kit.map {
            SorobanLatestLedgerSource(rpcUrl: $0.config.rpcUrl)
        }
        let decimalsResolver: (any TokenDecimalsResolverType)? = demoState.kit.map {
            TokenDecimalsResolverAdapter($0.transactionOperations)
        }
        return ContextRuleFlow(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: manager,
            smartAccountExecutor: executor,
            webAuthnProvider: demoState.webAuthnProvider,
            webAuthnVerifierAddress: demoState.kit?.config.webauthnVerifierAddress,
            ed25519VerifierAddress: DemoConfig.ed25519VerifierAddress,
            ledgerSource: ledger,
            rpcUrl: demoState.kit?.config.rpcUrl,
            tokenDecimalsResolver: decimalsResolver
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - DelegateToAgentFlow
    // -------------------------------------------------------------------------

    /// Creates a `DelegateToAgentFlow` wrapping a fully-wired `ContextRuleFlow`.
    ///
    /// Reuses ``makeContextRuleBuilderFlow(demoState:activityLog:)`` so the
    /// delegate composition (Ed25519 signer + spending-limit policy + validUntil)
    /// submits through the same `addContextRule` path as the builder screen.
    @MainActor
    public static func makeDelegateToAgentFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> DelegateToAgentFlow {
        DelegateToAgentFlow(
            contextRuleFlow: makeContextRuleBuilderFlow(demoState: demoState, activityLog: activityLog),
            activityLog: activityLog
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - ApprovalInboxFlow
    // -------------------------------------------------------------------------

    /// Creates an `ApprovalInboxFlow` wired to the demo's coordination client and
    /// the kit's single-signer contract-call path.
    ///
    /// The contract-call provider resolves lazily on each call so a kit that
    /// becomes available after this flow is constructed is picked up without
    /// rebuilding the flow. Returns `nil` from the provider when no kit exists,
    /// which the flow surfaces as a "no wallet connected" error.
    @MainActor
    public static func makeApprovalInboxFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> ApprovalInboxFlow {
        let coordination = demoState.coordinationClient
            ?? URLSessionCoordinationClient(baseURL: DemoConfig.coordinationURL, token: DemoConfig.coordinationToken)
        return ApprovalInboxFlow(
            coordination: coordination,
            activityLog: activityLog,
            demoState: demoState,
            contractCallProvider: { @MainActor in
                demoState.kit.map { ContractCallOperationsAdapter($0.transactionOperations) }
            },
            // The agent flow scopes the delegation to the demo token, so decoded
            // consent amounts are formatted at the demo token's configured scale.
            tokenDecimals: Int(DemoConfig.demoTokenDecimals)
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - AccountSignersFlow
    // -------------------------------------------------------------------------

    /// Creates an `AccountSignersFlow` wired to the kit's context rule manager.
    @MainActor
    public static func makeAccountSignersFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> AccountSignersFlow {
        let manager: (any ContextRuleManagerType)? = demoState.kit.map {
            ContextRuleManagerAdapter($0.contextRuleManager)
        }
        return AccountSignersFlow(
            demoState: demoState,
            activityLog: activityLog,
            contextRuleManager: manager
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - ApproveFlow
    // -------------------------------------------------------------------------

    /// Creates an `ApproveFlow` with all adapters wired from the kit.
    @MainActor
    public static func makeApproveFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> ApproveFlow {
        let contractOps: any ContractCallOperationsType
        let multiOps: any MultiSignerContractCallType
        let ctxManager: (any ContextRuleManagerType)?
        let allowanceFetcher: (any AllowanceFetcherType)?

        if let kit = demoState.kit {
            contractOps = ContractCallOperationsAdapter(kit.transactionOperations)
            multiOps = MultiSignerContractCallAdapter(kit.multiSignerManager)
            ctxManager = ContextRuleManagerAdapter(kit.contextRuleManager)
            allowanceFetcher = SorobanAllowanceFetcher()
        } else {
            contractOps = NoOpContractCallOperations()
            multiOps = NoOpMultiSignerContractCall()
            ctxManager = nil
            allowanceFetcher = nil
        }
        return ApproveFlow(
            demoState: demoState,
            activityLog: activityLog,
            contractCallOperations: contractOps,
            multiSignerOperations: multiOps,
            contextRuleManager: ctxManager,
            allowanceFetcher: allowanceFetcher
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - TransferFlow
    // -------------------------------------------------------------------------

    /// Creates a `TransferFlow` with all adapters wired from the kit.
    @MainActor
    public static func makeTransferFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> TransferFlow {
        let txOps: any TransactionOperationsType
        let multiOps: any MultiSignerManagerType
        let ctxManager: (any ContextRuleManagerType)?

        if let kit = demoState.kit {
            txOps = TransactionOperationsAdapter(kit.transactionOperations)
            multiOps = MultiSignerManagerAdapter(kit.multiSignerManager)
            ctxManager = ContextRuleManagerAdapter(kit.contextRuleManager)
        } else {
            txOps = NoOpTransactionOperations()
            multiOps = NoOpMultiSignerManager()
            ctxManager = nil
        }
        let mainFlow = makeMainScreenFlow(demoState: demoState, activityLog: activityLog)
        return TransferFlow(
            demoState: demoState,
            activityLog: activityLog,
            transactionOperations: txOps,
            multiSignerManager: multiOps,
            contextRuleManager: ctxManager,
            mainScreenFlow: mainFlow
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - WalletConnectionFlow
    // -------------------------------------------------------------------------

    /// Creates a `WalletConnectionFlow` wired to the kit's wallet operations.
    @MainActor
    public static func makeWalletConnectionFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> WalletConnectionFlow {
        let ops: any ConnectionOperationsType = demoState.kit.map {
            ConnectionOperationsAdapter($0)
        } ?? NilConnectionOperations()
        let mainFlow = makeMainScreenFlow(demoState: demoState, activityLog: activityLog)
        return WalletConnectionFlow(
            demoState: demoState,
            activityLog: activityLog,
            operations: ops,
            mainScreenFlow: mainFlow
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - WalletCreationFlow
    // -------------------------------------------------------------------------

    /// Creates a `WalletCreationFlow` wired to the kit's wallet operations.
    ///
    /// Returns `nil` when no kit is initialized — callers should guard on
    /// `demoState.kit != nil` before invoking creation operations.
    @MainActor
    public static func makeWalletCreationFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> WalletCreationFlow? {
        guard let kit = demoState.kit else { return nil }
        let ops = WalletOperationsAdapter(kit.walletOperations)
        let tokenService = makeDemoTokenService(activityLog: activityLog)
        let mainFlow = makeMainScreenFlow(demoState: demoState, activityLog: activityLog)
        return WalletCreationFlow(
            demoState: demoState,
            activityLog: activityLog,
            walletOperations: ops,
            demoTokenService: tokenService,
            mainScreenFlow: mainFlow
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Ledger source
    // -------------------------------------------------------------------------

    /// Creates a `SorobanLatestLedgerSource` from the kit's RPC URL.
    ///
    /// Returns `nil` when no kit is initialized.
    @MainActor
    public static func makeLedgerSource(demoState: DemoState) -> SorobanLatestLedgerSource? {
        demoState.kit.map { SorobanLatestLedgerSource(rpcUrl: $0.config.rpcUrl) }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private helpers
    // -------------------------------------------------------------------------

    @MainActor
    private static func makeMainScreenFlow(
        demoState: DemoState,
        activityLog: ActivityLogState
    ) -> MainScreenFlow {
        MainScreenFlow(
            demoState: demoState,
            activityLog: activityLog,
            demoTokenService: makeDemoTokenService(activityLog: activityLog)
        )
    }
}
