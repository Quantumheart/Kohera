import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_poll_draft.dart';

/// Dialog for composing an MSC3381 poll before sending it.
///
/// Captures the question, 2–20 answer options, disclosed/undisclosed kind,
/// and single- vs. multi-select `maxSelections`. Returns a [KoheraPollDraft]
/// or `null` if cancelled. Sending is handled by the caller
/// ([ChatMessageActions.sendPoll]).
class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog._();

  static Future<KoheraPollDraft?> show(BuildContext context) {
    return showDialog<KoheraPollDraft?>(
      context: context,
      builder: (_) => const CreatePollDialog._(),
    );
  }

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  static const _minAnswers = 2;
  static const _maxAnswers = 20;

  final _questionController = TextEditingController();
  final List<TextEditingController> _answerControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _disclosed = true;
  bool _multiSelect = false;
  String? _error;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _answerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canAdd => _answerControllers.length < _maxAnswers;

  void _addAnswer() {
    if (!_canAdd) return;
    setState(() {
      _answerControllers.add(TextEditingController());
      _error = null;
    });
  }

  void _removeAnswer(int index) {
    if (_answerControllers.length <= _minAnswers) return;
    setState(() {
      _answerControllers[index].dispose();
      _answerControllers.removeAt(index);
      _error = null;
    });
  }

  KoheraPollDraft? _validate() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Enter a question.');
      return null;
    }
    final answers = _answerControllers.map((c) => c.text.trim()).toList();
    if (answers.any((a) => a.isEmpty)) {
      setState(() => _error = 'All options must have text.');
      return null;
    }
    final unique = answers.toSet();
    if (unique.length != answers.length) {
      setState(() => _error = 'Options must be unique.');
      return null;
    }
    if (answers.length < _minAnswers) {
      setState(() => _error = 'At least $_minAnswers options are required.');
      return null;
    }
    return KoheraPollDraft(
      question: question,
      answers: answers,
      disclosed: _disclosed,
      maxSelections: _multiSelect ? answers.length : 1,
    );
  }

  void _submit() {
    final draft = _validate();
    if (draft != null) Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Create poll'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _questionController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Question',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Text('Options', style: tt.titleSmall),
              const SizedBox(height: 8),
              for (var i = 0; i < _answerControllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _answerControllers[i],
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove option',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _answerControllers.length > _minAnswers
                            ? () => _removeAnswer(i)
                            : null,
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _canAdd ? _addAnswer : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disclosed (show live results)'),
                value: _disclosed,
                onChanged: (v) => setState(() {
                  _disclosed = v;
                  _error = null;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple selections'),
                value: _multiSelect,
                onChanged: _answerControllers.length > 1
                    ? (v) => setState(() {
                          _multiSelect = v;
                          _error = null;
                        })
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: tt.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
