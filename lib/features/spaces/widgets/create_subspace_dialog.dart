import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/spaces/widgets/space_wizard.dart';
import 'package:matrix/matrix.dart';

class CreateSubspaceDialog {
  const CreateSubspaceDialog._();

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    required Room parentSpace,
  }) {
    return SpaceWizard.show(
      context,
      matrixService: matrixService,
      parentSpace: parentSpace,
    );
  }
}
