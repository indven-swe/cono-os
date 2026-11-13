import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/daily_request_quota.dart';
import '../ai/cono_model_tier.dart';
import '../ai/cono_model_runtime.dart';
import '../bridge/host_bridge.dart';
import 'ladybird_browser_controller.dart';

class ConoAppPage extends StatelessWidget {
  const ConoAppPage({
    required this.name,
    required this.preferences,
    required this.quota,
    required this.browserController,
    required this.onOpenWebsite,
    required this.onBack,
    this.embedded = false,
    super.key,
  });

  final String name;
  final SharedPreferences preferences;
  final DailyRequestQuota quota;
  final LadybirdBrowserController browserController;
  final ValueChanged<Uri> onOpenWebsite;
  final VoidCallback onBack;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = switch (name) {
      'Notes' => NotesApp(preferences: preferences),
      'Calculator' => const CalculatorApp(),
      'Cono AI' => ConoAiApp(quota: quota, onOpenWebsite: onOpenWebsite),
      'Bridge' => BridgeApp(preferences: preferences),
      'Files' => const FilesApp(),
      'Ladybird' => LadybirdApp(controller: browserController),
      'Paint' => const PaintApp(),
      _ => _ComingSoonApp(name: name),
    };

    if (embedded) {
      return app;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to apps',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              const Icon(Icons.more_horiz, color: Colors.white54),
            ],
          ),
        ),
        Expanded(child: app),
      ],
    );
  }
}

class NotesApp extends StatefulWidget {
  const NotesApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.preferences.getString('cono_note') ?? '',
  );
  bool _saved = true;
  String? _saveError;

  void _save(String value) {
    setState(() {
      _saved = false;
      _saveError = null;
    });
    unawaited(_persist(value));
  }

  Future<void> _persist(String value) async {
    try {
      final saved = await widget.preferences.setString('cono_note', value);
      if (!saved) {
        throw Exception('The note could not be saved.');
      }
      if (mounted) {
        setState(() => _saved = true);
      }
    } on Exception catch (error) {
      debugPrint('Could not save note: $error');
      if (mounted) {
        setState(() => _saveError = 'Save failed');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: _panelDecoration(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('QUICK NOTE', style: TextStyle(letterSpacing: 1.4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        _saveError != null
                            ? Icons.error_outline
                            : _saved
                                ? Icons.cloud_done_outlined
                                : Icons.sync,
                        size: 16,
                        color: _saveError == null
                            ? Colors.white54
                            : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _saveError ??
                              (_saved ? 'Saved on this device' : 'Saving...'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: _saveError == null
                                ? Colors.white54
                                : Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: _save,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Start writing...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(height: 1.6, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({super.key});

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  String _display = '0';
  double? _storedValue;
  String? _operator;
  bool _replaceDisplay = false;

  void _press(String key) {
    setState(() {
      if (key == 'AC') {
        _display = '0';
        _storedValue = null;
        _operator = null;
        _replaceDisplay = false;
      } else if (key == '+/-') {
        if (_display != '0') {
          _display =
              _display.startsWith('-') ? _display.substring(1) : '-$_display';
        }
      } else if (key == '%') {
        final value = double.tryParse(_display);
        if (value != null) {
          _display = _format(value / 100);
        }
      } else if (const {'+', '−', '×', '÷'}.contains(key)) {
        final value = double.tryParse(_display);
        if (value == null) {
          return;
        }
        _storedValue = value;
        _operator = key;
        _replaceDisplay = true;
      } else if (key == '=') {
        _calculate();
      } else {
        _enterDigit(key);
      }
    });
  }

  void _enterDigit(String digit) {
    if (digit == '.' && !_replaceDisplay && _display.contains('.')) {
      return;
    }
    if (_replaceDisplay) {
      _display = digit == '.' ? '0.' : digit;
      _replaceDisplay = false;
      return;
    }

    if (digit == '.') {
      _display = '$_display.';
    } else if (_display == '0') {
      _display = digit;
    } else if (_display.length < 14) {
      _display += digit;
    }
  }

  void _calculate() {
    final left = _storedValue;
    final right = double.tryParse(_display);
    final operator = _operator;
    if (left == null || right == null || operator == null) {
      return;
    }

    final result = switch (operator) {
      '+' => left + right,
      '−' => left - right,
      '×' => left * right,
      '÷' => right == 0 ? double.nan : left / right,
      _ => right,
    };
    _display = result.isFinite ? _format(result) : 'Error';
    _storedValue = null;
    _operator = null;
    _replaceDisplay = true;
  }

  String _format(double value) {
    if (value.abs() >= 1e12 || (value != 0 && value.abs() < 1e-8)) {
      return value.toStringAsExponential(4);
    }
    return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['AC', '+/-', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['0', '.', '='],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: _panelDecoration(),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _display,
                        key: const ValueKey('calculator-display'),
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                for (final row in keys)
                  Expanded(
                    child: Row(
                      children: [
                        for (final key in row)
                          Expanded(
                            flex: key == '0' ? 2 : 1,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _CalculatorKey(
                                label: key,
                                emphasized: const {'+', '−', '×', '÷', '='}
                                    .contains(key),
                                onPressed: () => _press(key),
                              ),
                            ),
                          ),
                        if (row.length == 3) const Spacer(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalculatorKey extends StatelessWidget {
  const _CalculatorKey({
    required this.label,
    required this.onPressed,
    required this.emphasized,
  });

  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: emphasized
              ? Colors.white.withOpacity(0.19)
              : Colors.white.withOpacity(0.07),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

class BridgeApp extends StatefulWidget {
  const BridgeApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<BridgeApp> createState() => _BridgeAppState();
}

class _BridgeAppState extends State<BridgeApp> {
  static const _storageKey = 'cono_bridge_shortcuts_v1';

  final _bridge = HostBridge();
  late List<_ExternalShortcut> _shortcuts = _loadShortcuts();

  List<_ExternalShortcut> _loadShortcuts() {
    final raw = widget.preferences.getString(_storageKey);
    if (raw == null) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Stored Bridge shortcuts are invalid.');
    }

    return decoded.map((item) {
      if (item is! Map<String, dynamic> ||
          item['name'] is! String ||
          item['uri'] is! String) {
        throw const FormatException('Stored Bridge shortcut is invalid.');
      }
      final uri = Uri.tryParse(item['uri'] as String);
      if (uri == null || !HostBridge.supportsUri(uri)) {
        throw const FormatException('Stored Bridge link is not allowed.');
      }
      return _ExternalShortcut(item['name'] as String, uri);
    }).toList();
  }

  Future<void> _addShortcut() async {
    final nameController = TextEditingController();
    final uriController = TextEditingController();
    try {
      final draft = await showDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add a host shortcut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: uriController,
                decoration: const InputDecoration(
                  labelText: 'HTTPS link or app URL scheme',
                  hintText: 'https://example.com or appname://',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (nameController.text.trim(), uriController.text.trim()),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (draft == null || !mounted) {
        return;
      }

      final uri = Uri.tryParse(draft.$2);
      if (draft.$1.isEmpty || uri == null || !HostBridge.supportsUri(uri)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a name and a supported external link.'),
          ),
        );
        return;
      }

      final shortcut = _ExternalShortcut(draft.$1, uri);
      final updated = [..._shortcuts, shortcut];
      final saved = await widget.preferences.setString(
        _storageKey,
        jsonEncode(
          updated
              .map((item) => {'name': item.name, 'uri': item.uri.toString()})
              .toList(),
        ),
      );
      if (!saved) {
        throw Exception('Could not save Bridge shortcut.');
      }
      if (mounted) {
        setState(() => _shortcuts = updated);
      }
    } on Exception catch (error) {
      debugPrint('Could not add Bridge shortcut: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The shortcut could not be saved.')),
        );
      }
    } finally {
      nameController.dispose();
      uriController.dispose();
    }
  }

  Future<void> _launch(_ExternalShortcut shortcut) async {
    try {
      final opened = await _bridge.launchExternalUri(shortcut.uri);
      if (mounted && !opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('The host could not open this shortcut.')),
        );
      }
    } on PlatformException catch (error) {
      debugPrint('Host shortcut launch failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('The host could not open this shortcut.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: _panelDecoration(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add and launch shortcuts you register on this device.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addShortcut,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'ConoOS does not enumerate installed apps. iOS only opens links or schemes supported by the host and the target app.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _shortcuts.isEmpty
                  ? const Center(
                      child: Text(
                        'No shortcuts yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _shortcuts.length,
                      itemBuilder: (context, index) {
                        final shortcut = _shortcuts[index];
                        return ListTile(
                          leading: const Icon(Icons.launch),
                          title: Text(shortcut.name),
                          subtitle: Text(
                            shortcut.uri.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Open ${shortcut.name}',
                            onPressed: () => _launch(shortcut),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExternalShortcut {
  const _ExternalShortcut(this.name, this.uri);

  final String name;
  final Uri uri;
}

class FilesApp extends StatefulWidget {
  const FilesApp({super.key});

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  List<PlatformFile> _selectedFiles = [];
  bool _isPicking = false;

  Future<void> _pickFiles() async {
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (mounted && result != null) {
        setState(() => _selectedFiles = result.files);
      }
    } on PlatformException catch (error) {
      debugPrint('File picker failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The file picker is unavailable here.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: _panelDecoration(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose files to view them in this workspace.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isPicking ? null : _pickFiles,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: const Text('Choose files'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'ConoOS only lists files you select. File access is not recursive.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _selectedFiles.isEmpty
                  ? const Center(
                      child: Text(
                        'No files selected',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _selectedFiles.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        return ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(file.name),
                          subtitle: Text(_formatFileSize(file.size)),
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class LadybirdApp extends StatefulWidget {
  const LadybirdApp({required this.controller, super.key});

  final LadybirdBrowserController controller;

  @override
  State<LadybirdApp> createState() => _LadybirdAppState();
}

class _LadybirdAppState extends State<LadybirdApp> {
  final _addressController = TextEditingController();
  InAppWebViewController? _webViewController;
  var _progress = 0;
  var _canGoBack = false;
  var _canGoForward = false;
  String? _error;
  bool get _supportsEmbeddedView =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onNavigationRequested);
    _syncAddress(widget.controller.currentUri);
    if (!_supportsEmbeddedView && widget.controller.currentUri != null) {
      unawaited(_onNavigationRequested());
    }
  }

  @override
  void didUpdateWidget(covariant LadybirdApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onNavigationRequested);
      widget.controller.addListener(_onNavigationRequested);
      _syncAddress(widget.controller.currentUri);
    }
  }

  void _syncAddress(Uri? uri) {
    if (uri != null) {
      _addressController.text = uri.toString();
    }
  }

  Future<void> _onNavigationRequested() async {
    final uri = widget.controller.currentUri;
    _syncAddress(uri);
    if (uri == null) {
      return;
    }

    try {
      if (!_supportsEmbeddedView) {
        if (uri.scheme != 'https') {
          if (mounted) {
            setState(
              () => _error =
                  'The host-browser fallback only supports HTTPS pages.',
            );
          }
          return;
        }
        final launched = await HostBridge().openWebLink(uri);
        if (mounted) {
          setState(
            () => _error = launched
                ? 'Opened in the host browser; embedded Ladybird is unavailable here.'
                : 'No host browser could open this page.',
          );
        }
        return;
      }
      await _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Ladybird could not open $uri: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = 'Ladybird could not load this page.');
      }
    }
  }

  Future<void> _openAddress(String value) async {
    final uri = LadybirdAddress.resolve(value);
    if (uri == null) {
      setState(() => _error = 'Enter a valid web address or search term.');
      return;
    }
    _error = null;
    widget.controller.navigate(uri);
  }

  Future<void> _updateHistoryState() async {
    final webView = _webViewController;
    if (webView == null) {
      return;
    }
    final canGoBack = await webView.canGoBack();
    final canGoForward = await webView.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onNavigationRequested);
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: _panelDecoration(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: _canGoBack
                      ? () async {
                          await _webViewController?.goBack();
                          await _updateHistoryState();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: _canGoForward
                      ? () async {
                          await _webViewController?.goForward();
                          await _updateHistoryState();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('ladybird-address'),
                    controller: _addressController,
                    onSubmitted: _openAddress,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      hintText: 'Search or enter an address',
                      prefixIcon: const Icon(Icons.language),
                      suffixIcon: IconButton(
                        tooltip: 'Go',
                        onPressed: () => _openAddress(_addressController.text),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: () async {
                    if (_webViewController == null) {
                      await _openAddress(_addressController.text);
                    } else {
                      await _webViewController!.reload();
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SizedBox(
              height: 2,
              child: _progress < 100
                  ? LinearProgressIndicator(value: _progress / 100)
                  : null,
            ),
            if (_error case final error?) ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
            Expanded(
              child: _supportsEmbeddedView
                  ? InAppWebView(
                      key: const ValueKey('ladybird-webview'),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        supportMultipleWindows: false,
                        useShouldOverrideUrlLoading: true,
                        isInspectable: false,
                      ),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        if (widget.controller.currentUri != null) {
                          unawaited(_onNavigationRequested());
                        }
                      },
                      onLoadStart: (controller, url) {
                        if (mounted) {
                          setState(() {
                            _progress = 0;
                            _error = null;
                            if (url != null) {
                              _addressController.text = url.toString();
                            }
                          });
                        }
                      },
                      onLoadStop: (controller, url) async {
                        if (mounted) {
                          setState(() => _progress = 100);
                          if (url != null) {
                            _addressController.text = url.toString();
                          }
                        }
                        await _updateHistoryState();
                      },
                      onProgressChanged: (controller, progress) {
                        if (mounted) {
                          setState(() => _progress = progress);
                        }
                      },
                      onReceivedError: (controller, request, error) {
                        if (request.isForMainFrame == true && mounted) {
                          setState(
                            () => _error =
                                'Page failed to load: ${error.description}',
                          );
                        }
                      },
                      shouldOverrideUrlLoading: (controller, action) async {
                        final uri = action.request.url?.uriValue;
                        return uri != null && LadybirdAddress.isWebAddress(uri)
                            ? NavigationActionPolicy.ALLOW
                            : NavigationActionPolicy.CANCEL;
                      },
                    )
                  : const Center(
                      child: Text(
                        'This platform opens pages in its host browser. '
                        'Embedded Ladybird is not available here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PaintApp extends StatefulWidget {
  const PaintApp({super.key});

  @override
  State<PaintApp> createState() => _PaintAppState();
}

class _PaintAppState extends State<PaintApp> {
  final GlobalKey _canvasKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  bool _isExporting = false;

  void _startStroke(DragStartDetails details) {
    setState(() => _strokes.add([details.localPosition]));
  }

  void _continueStroke(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() => _strokes.last.add(details.localPosition));
  }

  Future<void> _exportPng() async {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('The drawing surface is not ready to export.');
    }
    setState(() => _isExporting = true);
    try {
      final image = await renderObject.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        throw StateError('Could not encode the drawing as a PNG.');
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export drawing',
        fileName: 'cono-drawing.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drawing exported as PNG.')),
        );
      }
    } on PlatformException catch (error) {
      debugPrint('Paint export failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PNG export is unavailable here.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: _panelDecoration(),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Undo stroke',
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() => _strokes.removeLast()),
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Clear canvas',
                  onPressed:
                      _strokes.isEmpty ? null : () => setState(_strokes.clear),
                  icon: const Icon(Icons.delete_outline),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isExporting ? null : _exportPng,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export PNG'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onPanStart: _startStroke,
                  onPanUpdate: _continueStroke,
                  child: CustomPaint(
                    painter: _DrawingPainter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final points in strokes) {
      if (points.isEmpty) {
        continue;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (points.length == 1) {
        canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) =>
      !identical(strokes, oldDelegate.strokes);
}

class ConoAiApp extends StatefulWidget {
  const ConoAiApp({
    required this.quota,
    this.runtime,
    this.onOpenWebsite,
    super.key,
  });

  final DailyRequestQuota quota;
  final ConoModelRuntime? runtime;
  final ValueChanged<Uri>? onOpenWebsite;

  @override
  State<ConoAiApp> createState() => _ConoAiAppState();
}

class _ConoAiAppState extends State<ConoAiApp> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  late final ConoModelRuntime _runtime =
      widget.runtime ?? LocalConoModelRuntime();
  late ConoModelTier _selectedTier = widget.quota.selectedTier;
  late int _remaining = widget.quota.remaining;
  bool _modelAvailable = false;
  bool _isGenerating = false;
  bool _isImporting = false;
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text: 'Hi, I’m Cono. My chat will use only ${ConoModelTier.modelName}, '
          'trained from scratch for ConoOS. Say “open example.com” or '
          '“search for cats” to open Ladybird.',
      fromUser: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshModelAvailability());
  }

  Future<void> _refreshModelAvailability() async {
    final tier = _selectedTier;
    try {
      final available = await _runtime.hasModel(tier);
      if (mounted && _selectedTier == tier) {
        setState(() => _modelAvailable = available);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not inspect Cono Nova model: $error\n$stackTrace');
      if (mounted && _selectedTier == tier) {
        setState(() => _modelAvailable = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not check the local model file.')),
        );
      }
    }
  }

  Future<void> _selectTier(ConoModelTier? tier) async {
    if (tier == null || tier == _selectedTier) {
      return;
    }
    try {
      await widget.quota.setTier(tier);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTier = tier;
        _remaining = widget.quota.remaining;
        _modelAvailable = false;
      });
      await _refreshModelAvailability();
    } on Object catch (error, stackTrace) {
      debugPrint('Could not save Cono AI model tier: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the selected model.')),
        );
      }
    }
  }

  Future<void> _importModel() async {
    if (_isGenerating || _isImporting) {
      return;
    }
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['onnx'],
      );
      final path = result?.files.single.path;
      if (path == null) {
        return;
      }
      await _runtime.installModel(path, _selectedTier);
      await _refreshModelAvailability();
    } on Object catch (error, stackTrace) {
      debugPrint('Could not import Cono Nova model: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import this model: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _send(String value) async {
    final text = value.trim();
    if (text.isEmpty || _isGenerating || _isImporting) {
      return;
    }
    final website = LadybirdAddress.command(text);
    if (website != null && widget.onOpenWebsite != null) {
      setState(() {
        _messages
          ..add(_ChatMessage(text: text, fromUser: true))
          ..add(
            _ChatMessage(
              text: 'Opening ${website.host} in Ladybird.',
              fromUser: false,
            ),
          );
        _input.clear();
      });
      widget.onOpenWebsite!(website);
      _scrollToBottom();
      return;
    }
    if (!_modelAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Import this Cono Nova model before starting a chat.'),
        ),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final allowed = await widget.quota.tryConsume();
      if (!mounted) {
        return;
      }
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Today’s Cono AI request limit is used.')),
        );
        return;
      }

      setState(() {
        _messages.add(_ChatMessage(text: text, fromUser: true));
        _input.clear();
      });
      final conversation = [
        for (final message in _messages.skip(1))
          '${message.fromUser ? 'User' : 'Cono Nova'}: ${message.text}',
      ].join('\n');
      final answer = await _runtime.reply(conversation, _selectedTier);
      if (mounted) {
        setState(
            () => _messages.add(_ChatMessage(text: answer, fromUser: false)));
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Cono AI request failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _messages.add(
            const _ChatMessage(
              text: 'Cono Nova could not complete that request. No other AI '
                  'was used.',
              fromUser: false,
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _remaining = widget.quota.remaining;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    unawaited(_closeRuntime());
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _closeRuntime() async {
    try {
      await _runtime.close();
    } on Object catch (error, stackTrace) {
      debugPrint('Could not close Cono Nova runtime: $error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: _panelDecoration(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ConoModelTier.modelName} · ${_selectedTier.label} · '
                    '${_selectedTier.parameterLabel}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<ConoModelTier>(
                    value: _selectedTier,
                    onChanged:
                        _isGenerating || _isImporting ? null : _selectTier,
                    items: [
                      for (final tier in ConoModelTier.values)
                        DropdownMenuItem(
                          value: tier,
                          child: Text(
                            '${tier.label} · ${tier.parameterLabel}'
                            '${tier.requiresSeparateInstall ? ' · Install' : ''}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedTier.dailyRequestLimit} requests per day',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isGenerating || _isImporting ? null : _importModel,
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: Text(
                  _isImporting
                      ? 'Importing...'
                      : _modelAvailable
                          ? 'Replace model'
                          : 'Import model',
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.fromUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: message.fromUser
                            ? Colors.white.withOpacity(0.16)
                            : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(message.text),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: _send,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Ask Cono...',
                      prefixIcon: Icon(Icons.auto_awesome),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _isGenerating || _isImporting
                      ? null
                      : () => _send(_input.text),
                  icon: _isGenerating || _isImporting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${ConoModelTier.modelName} ${_selectedTier.label}: '
              '${_modelAvailable ? 'installed on this device' : 'model not installed'}. '
              'No other AI is used. '
              'Requests today: ${_selectedTier.dailyRequestLimit - _remaining}/${_selectedTier.dailyRequestLimit}.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class DuoWorkspace extends StatefulWidget {
  const DuoWorkspace({
    required this.preferences,
    this.onOpenWebsite,
    super.key,
  });

  final SharedPreferences preferences;
  final ValueChanged<Uri>? onOpenWebsite;

  @override
  State<DuoWorkspace> createState() => _DuoWorkspaceState();
}

class _DuoWorkspaceState extends State<DuoWorkspace> {
  static const _apps = ['Notes', 'Calculator', 'Cono AI'];

  late final _quota = DailyRequestQuota(widget.preferences);
  String _firstApp = 'Notes';
  String _secondApp = 'Calculator';

  Widget _app(String name) => switch (name) {
        'Notes' => NotesApp(preferences: widget.preferences),
        'Calculator' => const CalculatorApp(),
        'Cono AI' => ConoAiApp(
            quota: _quota,
            onOpenWebsite: widget.onOpenWebsite,
          ),
        _ => const SizedBox.shrink(),
      };

  Widget _pane(String appName, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          DropdownButton<String>(
            value: appName,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: _apps
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(name),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _app(appName),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 700;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Run two built-in apps side by side.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Swap apps',
                    onPressed: () => setState(() {
                      final current = _firstApp;
                      _firstApp = _secondApp;
                      _secondApp = current;
                    }),
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Flex(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _pane(
                      _firstApp,
                      (value) {
                        if (value != null) {
                          setState(() => _firstApp = value);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: horizontal ? 14 : 0,
                    height: horizontal ? 0 : 14,
                  ),
                  Expanded(
                    child: _pane(
                      _secondApp,
                      (value) {
                        if (value != null) {
                          setState(() => _secondApp = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _ComingSoonApp extends StatelessWidget {
  const _ComingSoonApp({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_empty_rounded, size: 38),
            const SizedBox(height: 16),
            Text('$name is on the roadmap',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'This app is not implemented yet; no external app or file access is simulated.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration() => BoxDecoration(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
