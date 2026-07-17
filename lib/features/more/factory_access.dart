import 'package:flutter/material.dart';

import 'factory_screen.dart';

const factoryModePin = '1234';

Future<bool> requestFactoryModeAccess(BuildContext context) async {
  final controller = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Service Access',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: TextField(
        key: const Key('factory_pin_field'),
        controller: controller,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'PIN',
          hintStyle: TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => Navigator.pop(dialogContext, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          key: const Key('factory_pin_submit'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child:
              const Text('Continue', style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
  final allowed = submitted == true && controller.text == factoryModePin;
  if (!context.mounted) return false;
  if (allowed) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FactoryScreen()),
    );
  } else if (submitted == true) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: const Text('Incorrect PIN.',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return allowed;
}
