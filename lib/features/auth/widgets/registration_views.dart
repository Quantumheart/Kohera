import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/auth/services/registration_controller.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:url_launcher/url_launcher.dart';
// coverage:ignore-start

/// Builds content for UIA stages that appear after form submission.
Widget buildUiaContent({
  required BuildContext context,
  required RegistrationController controller,
}) {
  switch (controller.state) {
    case RegistrationState.enterEmail:
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Email verification is required by this server.'),
          SizedBox(height: 8),
          Text('This step is not yet supported.'),
        ],
      );

    case RegistrationState.recaptcha:
      return _buildRecaptchaView(context, controller);

    case RegistrationState.acceptTerms:
      return _buildTermsView(context, controller);

    default:
      return const SizedBox.shrink();
  }
}

// ── reCAPTCHA view ──────────────────────────────────────────────

Widget _buildRecaptchaView(
  BuildContext context,
  RegistrationController controller,
) {
  final tt = Theme.of(context).textTheme;

  if (controller.recaptchaWaiting) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KoheraLoader(),
        const SizedBox(height: 16),
        Text(
          'Complete the verification in your browser,\n'
          'then return to Kohera.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium,
        ),
      ],
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'This server requires a CAPTCHA to confirm you are human.',
        style: tt.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: controller.submitRecaptcha,
        icon: const Icon(KIcons.openInBrowser),
        label: const Text('Open CAPTCHA in browser'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
          ),
        ),
      ),
    ],
  );
}

// ── Terms of Service view ───────────────────────────────────────

Widget _buildTermsView(
  BuildContext context,
  RegistrationController controller,
) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final policies = controller.termsOfServicePolicies;

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'You must accept the Terms of Service to create an account.',
        style: tt.bodyMedium,
        textAlign: TextAlign.center,
      ),
      if (policies.isNotEmpty) ...[
        const SizedBox(height: 12),
        ...policies.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => launchUrl(
                Uri.parse(p.url),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(KIcons.openInNew, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      p.name,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: controller.submitTerms,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
          ),
        ),
        child: const Text('I agree to the Terms of Service'),
      ),
    ],
  );
}
// coverage:ignore-end
