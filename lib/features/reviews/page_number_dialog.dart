import 'package:flutter/material.dart';

/// Page-number dialog that owns its text controller.
///
/// The controller must outlive the dialog route's reverse animation. Creating
/// it in the caller and disposing it right after `showDialog` returns can use a
/// disposed controller while the route is still animating out.
class PageNumberDialog extends StatefulWidget {
  const PageNumberDialog({
    super.key,
    required this.initialPage,
    required this.title,
    required this.cancelLabel,
    required this.goLabel,
  });

  final int initialPage;
  final String title;
  final String cancelLabel;
  final String goLabel;

  @override
  State<PageNumberDialog> createState() => _PageNumberDialogState();
}

class _PageNumberDialogState extends State<PageNumberDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialPage}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(int.tryParse(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.goLabel)),
      ],
    );
  }
}
