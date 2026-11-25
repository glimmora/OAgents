import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:oagents/models/chat_message.dart';
import 'package:oagents/services/chat_controller.dart';
import 'package:oagents/widgets/permission_card.dart';
import 'package:oagents/widgets/status_card.dart';

/// Layar percakapan: daftar pesan (ListView.builder) + input.
/// SEMUA umpan balik tampil sebagai kartu StatusCard/PermissionCard inline
/// di daftar pesan — bukan popup notifikasi melayang.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _send(ChatController c) async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _jumpToBottom();
    await c.sendPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    _jumpOnNewMessages(controller);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OAgents'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: controller.sessionId == null
                ? const Text(
                    'tanpa sesi',
                    style: TextStyle(fontSize: 12),
                  )
                : Text(
                    'sesi: ${_shortId(controller.sessionId!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: controller.messages.isEmpty
                ? _EmptyChatView(sessionId: controller.sessionId)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, i) => _MessageTile(
                      message: controller.messages[i],
                      onDecision: controller.decidePermission,
                    ),
                  ),
          ),
          _InputBar(
            controller: _input,
            sending: controller.sending,
            onSend: () => _send(controller),
          ),
        ],
      ),
    );
  }

  void _jumpOnNewMessages(ChatController controller) {
    // Gulir ke bawah tiap kali jumlah pesan bertambah (streaming real-time).
    final count = controller.messages.length;
    if (_lastCount != count) {
      _lastCount = count;
      _jumpToBottom();
    }
  }

  int _lastCount = 0;

  static String _shortId(String id) =>
      id.length <= 10 ? id : '${id.substring(0, 8)}…';
}

class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView({required this.sessionId});

  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          StatusCard(
            title: sessionId == null ? 'Belum ada sesi' : 'Sesi siap',
            detail: sessionId == null
                ? 'Kirim pesan pertama untuk membuat sesi baru di server '
                      'opencode. Pastikan runtime sudah terpasang dan server '
                      'berjalan di tab Runtime.'
                : 'Belum ada pesan pada sesi ini. Ketik di bawah untuk '
                      'mulai berbicara dengan agent.',
            icon: 'chat',
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.onDecision});

  final ChatMessage message;
  final Future<void> Function(PermissionRequest, bool) onDecision;

  @override
  Widget build(BuildContext context) {
    if (message.permissionRequest != null) {
      return PermissionCard(
        request: message.permissionRequest!,
        onDecision: (r, a) => onDecision(r, a),
      );
    }
    if (message.role == ChatRole.system) {
      // Kartu status inline — satu-satunya kanal umpan balik UI.
      return StatusCard(
        title: message.text,
        detail: message.pending ? 'sedang berjalan…' : null,
        icon: message.error ? 'error' : 'info',
        tone: message.error ? StatusTone.error : StatusTone.info,
        compact: true,
      );
    }
    final isUser = message.role == ChatRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            if (message.text.isEmpty && message.pending)
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'agent sedang berpikir…',
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            for (final call in message.toolCalls)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ToolCallRow(call: call),
              ),
            if (message.pending && message.toolCalls.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: 34,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolCallRow extends StatelessWidget {
  const _ToolCallRow({required this.call});

  final ToolCallView call;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            call.running ? Icons.build_circle_outlined : Icons.task_alt,
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              call.running ? '${call.tool}: ${call.input}' : '${call.tool}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.8),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Tulis pesan ke agent…',
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
