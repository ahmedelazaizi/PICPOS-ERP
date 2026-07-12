part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// APPROVAL WORKFLOW DAO — سير عمل الاعتمادات
// Multi-Level Approval: Maker → Checker → Approver
// ═══════════════════════════════════════════════════════════════════════════

extension ApprovalWorkflowDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // WORKFLOW TEMPLATE MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Create an approval workflow template
  Future<int> createWorkflowTemplate({
    required String name,
    required String entityType,
    required double amountThreshold,
    required int requiredLevels,
    required List<Map<String, dynamic>> steps,
  }) async {
    return transaction(() async {
      final wfId = await into(approvalWorkflows).insert(
        ApprovalWorkflowsCompanion.insert(
          name: name,
          entityType: entityType,
          amountThreshold: Value(amountThreshold),
          requiredLevels: Value(requiredLevels),
        ),
      );

      for (final step in steps) {
        await into(approvalSteps).insert(
          ApprovalStepsCompanion.insert(
            workflowId: wfId,
            stepOrder: step['order'] as int,
            stepName: step['name'] as String,
            roleId: Value(step['roleId'] as int?),
            userId: Value(step['userId'] as int?),
          ),
        );
      }

      return wfId;
    });
  }

  /// Get all active workflows
  Future<List<ApprovalWorkflowData>> getActiveWorkflows() {
    return (select(approvalWorkflows)
          ..where((w) => w.isActive.equals(true)))
        .get();
  }

  /// Get workflow steps
  Future<List<ApprovalStepData>> getWorkflowSteps(int workflowId) {
    return (select(approvalSteps)
          ..where((s) => s.workflowId.equals(workflowId))
          ..orderBy([(s) => OrderingTerm.asc(s.stepOrder)]))
        .get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APPROVAL REQUEST MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit an entity for approval
  /// Automatically finds the applicable workflow based on type and amount
  Future<int?> submitForApproval({
    required String entityType,
    required int entityId,
    required double amount,
    required int requestedBy,
    String? notes,
  }) async {
    // Find applicable workflow
    final workflows = await customSelect(
      '''SELECT * FROM approval_workflows
         WHERE entity_type = ? AND amount_threshold <= ? AND is_active = 1
         ORDER BY amount_threshold DESC LIMIT 1''',
      variables: [Variable(entityType), Variable(amount)],
    ).getSingleOrNull();

    if (workflows == null) return null; // No workflow applies

    final workflowId = workflows.data['id'] as int;

    return into(approvalRequests).insert(
      ApprovalRequestsCompanion.insert(
        workflowId: workflowId,
        entityType: entityType,
        entityId: entityId,
        amount: Value(amount),
        requestedBy: requestedBy,
        notes: Value(notes),
      ),
    );
  }

  /// Process an approval decision (approve or reject)
  Future<void> processDecision({
    required int requestId,
    required int decidedBy,
    required String decision, // 'approved' or 'rejected'
    String? comments,
  }) async {
    await transaction(() async {
      final request = await (select(approvalRequests)
            ..where((r) => r.id.equals(requestId)))
          .getSingle();

      // Get current step
      final steps = await getWorkflowSteps(request.workflowId);
      final currentStepData = steps.firstWhere(
        (s) => s.stepOrder == request.currentStep,
      );

      // Record the decision
      await into(approvalDecisions).insert(
        ApprovalDecisionsCompanion.insert(
          requestId: requestId,
          stepId: currentStepData.id,
          decidedBy: decidedBy,
          decision: decision,
          comments: Value(comments),
        ),
      );

      if (decision == 'rejected') {
        // Reject the entire request
        await (update(approvalRequests)
              ..where((r) => r.id.equals(requestId)))
            .write(ApprovalRequestsCompanion(
          status: const Value('rejected'),
          completedAt: Value(DateTime.now()),
        ));
      } else {
        // Check if this is the last step
        final isLastStep = request.currentStep >= steps.length;
        if (isLastStep) {
          // Fully approved
          await (update(approvalRequests)
                ..where((r) => r.id.equals(requestId)))
              .write(ApprovalRequestsCompanion(
            status: const Value('approved'),
            completedAt: Value(DateTime.now()),
          ));
        } else {
          // Move to next step
          await (update(approvalRequests)
                ..where((r) => r.id.equals(requestId)))
              .write(ApprovalRequestsCompanion(
            currentStep: Value(request.currentStep + 1),
          ));
        }
      }
    });
  }

  /// Get pending approvals for a user
  Future<List<ApprovalRequestData>> getPendingApprovalsForUser(int userId) async {
    // Get user's role
    final user = await (select(users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) return [];

    // Find requests where current step matches user's role or user specifically
    return customSelect(
      '''SELECT ar.* FROM approval_requests ar
         JOIN approval_steps ast ON ar.workflow_id = ast.workflow_id
           AND ar.current_step = ast.step_order
         WHERE ar.status = 'pending'
           AND (ast.user_id = ? OR ast.role_id = ?)
         ORDER BY ar.created_at DESC''',
      variables: [Variable(userId), Variable(user.roleId ?? 0)],
    ).get().then((rows) => rows.map((r) => ApprovalRequestData(
      id: r.data['id'] as int,
      workflowId: r.data['workflow_id'] as int,
      entityType: r.data['entity_type'] as String,
      entityId: r.data['entity_id'] as int,
      amount: (r.data['amount'] as num).toDouble(),
      currentStep: r.data['current_step'] as int,
      status: r.data['status'] as String,
      requestedBy: r.data['requested_by'] as int,
      notes: r.data['notes'] as String?,
      createdAt: () { final v = r.data['created_at']; return v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch((v as int) * 1000); }(),
      completedAt: null,
    )).toList());
  }

  /// Check if an entity requires approval
  Future<bool> requiresApproval(String entityType, double amount) async {
    final result = await customSelect(
      '''SELECT COUNT(*) as cnt FROM approval_workflows
         WHERE entity_type = ? AND amount_threshold <= ? AND is_active = 1''',
      variables: [Variable(entityType), Variable(amount)],
    ).getSingle();
    return ((result.data['cnt'] as int?) ?? 0) > 0;
  }

  /// Check if an entity is fully approved
  Future<bool> isApproved(String entityType, int entityId) async {
    final result = await customSelect(
      '''SELECT status FROM approval_requests
         WHERE entity_type = ? AND entity_id = ?
         ORDER BY created_at DESC LIMIT 1''',
      variables: [Variable(entityType), Variable(entityId)],
    ).getSingleOrNull();

    if (result == null) return true; // No approval required
    return result.data['status'] == 'approved';
  }

  /// Get stale pending requests for a workflow (used by escalation engine)
  Future<List<Map<String, dynamic>>> getStaleApprovalRequests({
    required int workflowId,
    required int cutoffEpoch,
  }) async {
    final results = await customSelect(
      '''SELECT ar.id, ar.current_step FROM approval_requests ar
         WHERE ar.workflow_id = ? AND ar.status = 'pending'
           AND ar.created_at < ?''',
      variables: [Variable(workflowId), Variable(cutoffEpoch)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Escalate a request to the next step
  Future<void> escalateApprovalRequest({
    required int requestId,
    required int newStep,
  }) async {
    await customStatement(
      'UPDATE approval_requests SET current_step = ? WHERE id = ?',
      [newStep, requestId],
    );
  }
}
