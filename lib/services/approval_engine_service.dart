import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';

/// Dynamic Approval Engine — محرك الاعتماد الهرمي الديناميكي
///
/// Evaluates JSON condition rules to determine the appropriate workflow,
/// supports auto-approval for small amounts, and escalation for stale requests.
class ApprovalEngineService {
  final AppDatabase _db;

  ApprovalEngineService(this._db);

  // ═══════════════════════════════════════════════════════════════════════
  // RULE EVALUATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Evaluate which workflow applies based on entity type, amount, and metadata.
  /// Returns the matching workflow or null if no workflow matches.
  Future<ApprovalWorkflowData?> evaluateRules({
    required String entityType,
    required double amount,
    Map<String, dynamic>? metadata,
  }) async {
    final workflows = await _db.getActiveWorkflows();

    // Filter workflows matching entity type
    final matching = workflows
        .where((w) => w.entityType == entityType)
        .toList();

    if (matching.isEmpty) return null;

    // Sort by specificity: workflows with conditions first, then by highest threshold
    matching.sort((a, b) {
      final aHasRules = a.conditionRules != null && a.conditionRules!.isNotEmpty;
      final bHasRules = b.conditionRules != null && b.conditionRules!.isNotEmpty;
      if (aHasRules && !bHasRules) return -1;
      if (!aHasRules && bHasRules) return 1;
      return b.amountThreshold.compareTo(a.amountThreshold);
    });

    for (final wf in matching) {
      // Check amount threshold
      if (amount < wf.amountThreshold) continue;

      // Check condition rules if they exist
      if (wf.conditionRules != null && wf.conditionRules!.isNotEmpty) {
        try {
          final rules = json.decode(wf.conditionRules!) as List;
          if (_evaluateConditions(rules, amount, metadata ?? {})) {
            return wf;
          }
        } catch (e) {
          debugPrint('[ApprovalEngine] Error parsing rules for wf ${wf.id}: $e');
          continue;
        }
      } else {
        // No conditions — amount threshold match is sufficient
        return wf;
      }
    }

    return null;
  }

  /// Evaluate a list of condition rules against provided data.
  /// All conditions must match (AND logic).
  bool _evaluateConditions(
    List<dynamic> conditions,
    double amount,
    Map<String, dynamic> metadata,
  ) {
    for (final cond in conditions) {
      if (cond is! Map) continue;
      final field = cond['field'] as String?;
      final op = cond['op'] as String?;
      final value = cond['value'];

      if (field == null || op == null || value == null) continue;

      // Get the actual value to compare
      dynamic actualValue;
      if (field == 'amount') {
        actualValue = amount;
      } else {
        actualValue = metadata[field];
      }

      if (actualValue == null) return false;

      if (!_compareValues(actualValue, op, value)) {
        return false;
      }
    }
    return true;
  }

  /// Compare two values using the specified operator.
  bool _compareValues(dynamic actual, String op, dynamic expected) {
    switch (op) {
      case '>':
        return (actual as num) > (expected as num);
      case '>=':
        return (actual as num) >= (expected as num);
      case '<':
        return (actual as num) < (expected as num);
      case '<=':
        return (actual as num) <= (expected as num);
      case '==':
        return actual.toString() == expected.toString();
      case '!=':
        return actual.toString() != expected.toString();
      case 'in':
        if (expected is List) {
          return expected.contains(actual.toString());
        }
        return false;
      default:
        return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AUTO-APPROVAL
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if an entity can be auto-approved (amount below threshold).
  /// Returns true if auto-approved (no manual approval needed).
  Future<bool> autoApproveIfEligible({
    required String entityType,
    required int entityId,
    required double amount,
    required int requestedBy,
  }) async {
    final workflows = await _db.getActiveWorkflows();

    // Find any workflow for this entity type with autoApproveBelow > 0
    for (final wf in workflows) {
      if (wf.entityType == entityType &&
          wf.autoApproveBelow > 0 &&
          amount <= wf.autoApproveBelow) {
        debugPrint(
          '[ApprovalEngine] Auto-approving $entityType #$entityId '
          '(amount $amount <= autoApproveBelow ${wf.autoApproveBelow})',
        );
        return true; // No approval needed
      }
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SMART SUBMISSION
  // ═══════════════════════════════════════════════════════════════════════

  /// Smart submit: evaluates rules, checks auto-approval, then submits if needed.
  /// Returns null if auto-approved, or the request ID if submitted for review.
  Future<int?> smartSubmit({
    required String entityType,
    required int entityId,
    required double amount,
    required int requestedBy,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    // Step 1: Check auto-approval
    final autoApproved = await autoApproveIfEligible(
      entityType: entityType,
      entityId: entityId,
      amount: amount,
      requestedBy: requestedBy,
    );
    if (autoApproved) return null;

    // Step 2: Evaluate rules to find matching workflow
    final workflow = await evaluateRules(
      entityType: entityType,
      amount: amount,
      metadata: metadata,
    );

    if (workflow == null) return null; // No workflow applies

    // Step 3: Submit for approval
    return _db.submitForApproval(
      entityType: entityType,
      entityId: entityId,
      amount: amount,
      requestedBy: requestedBy,
      notes: notes,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ESCALATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check for pending requests that have exceeded their escalation time.
  /// Returns a list of escalated request IDs.
  Future<List<int>> checkEscalation() async {
    final escalated = <int>[];
    final workflows = await _db.getActiveWorkflows();

    for (final wf in workflows) {
      if (wf.escalationHours <= 0) continue;

      // Find pending requests for this workflow that are stale
      final cutoffEpoch = DateTime.now()
          .subtract(Duration(hours: wf.escalationHours))
          .millisecondsSinceEpoch ~/ 1000;

      final staleRequests = await _db.getStaleApprovalRequests(
        workflowId: wf.id,
        cutoffEpoch: cutoffEpoch,
      );

      for (final req in staleRequests) {
        final requestId = req['id'] as int;
        final currentStep = req['current_step'] as int;
        final steps = await _db.getWorkflowSteps(wf.id);

        if (currentStep < steps.length) {
          // Escalate to next step
          await _db.escalateApprovalRequest(
            requestId: requestId,
            newStep: currentStep + 1,
          );
          escalated.add(requestId);
          debugPrint(
            '[ApprovalEngine] Escalated request #$requestId '
            'from step $currentStep to ${currentStep + 1}',
          );
        }
      }
    }

    return escalated;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WORKFLOW TEMPLATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Create a standard purchase workflow with auto-approve below threshold.
  /// Example: auto < 1000, checker required 1000-5000, GM > 5000
  Future<void> createPurchaseWorkflowTemplate({
    required double autoApproveBelow,
    required double checkerThreshold,
    required double gmThreshold,
    int? checkerRoleId,
    int? gmRoleId,
  }) async {
    // Standard checker workflow
    await _db.createWorkflowTemplate(
      name: 'اعتماد مشتريات — مراجع',
      entityType: 'purchase_order',
      amountThreshold: checkerThreshold,
      requiredLevels: 2,
      steps: [
        {'order': 1, 'name': 'المُعدّ', 'roleId': null, 'userId': null},
        {'order': 2, 'name': 'المراجع', 'roleId': checkerRoleId, 'userId': null},
      ],
    );

    // GM-level workflow for large amounts
    await _db.createWorkflowTemplate(
      name: 'اعتماد مشتريات — مدير عام',
      entityType: 'purchase_order',
      amountThreshold: gmThreshold,
      requiredLevels: 3,
      steps: [
        {'order': 1, 'name': 'المُعدّ', 'roleId': null, 'userId': null},
        {'order': 2, 'name': 'المراجع', 'roleId': checkerRoleId, 'userId': null},
        {'order': 3, 'name': 'المدير العام', 'roleId': gmRoleId, 'userId': null},
      ],
    );
  }
}
