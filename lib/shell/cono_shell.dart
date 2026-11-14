import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/daily_request_quota.dart';
import '../applications/cono_apps.dart';
import '../applications/ladybird_browser_controller.dart';

enum ShellSection { home, duo, search, apps, settings }

class ConoShell extends StatefulWidget {
  const ConoShell({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<ConoShell> createState() => _ConoShellState();
}

class _ConoShellState extends State<ConoShell> {
  ShellSection _section = ShellSection.home;
  String? _openApp;
  String _searchQuery = '';
  late final _quota = DailyRequestQuota(widget.preferences);
  final _ladybirdController = LadybirdBrowserController();
  final List<_DesktopWindow> _windows = [];

  static const _apps = <ConoAppInfo>[
    ConoAppInfo('Notes', Icons.sticky_note_2_outlined, 'Capture an idea'),
    ConoAppInfo('Calculator', Icons.calculate_outlined, 'Quick calculations'),
    ConoAppInfo('Cono AI', Icons.auto_awesome, 'Your local assistant'),
    ConoAppInfo('Bridge', Icons.link_rounded, 'Launch host shortcuts'),
    ConoAppInfo('Files', Icons.folder_outlined, 'Pick files you choose'),
    ConoAppInfo('Ladybird', Icons.language, 'Browse and search the web'),
    ConoAppInfo('Paint', Icons.brush_outlined, 'Draw and export PNGs'),
    ConoAppInfo('Settings', Icons.tune, 'Make ConoOS yours'),
  ];

  void _openWebsite(Uri uri) {
    _ladybirdController.navigate(uri);
    _open('Ladybird');
  }

  @override
  void dispose() {
    _ladybirdController.dispose();
    super.dispose();
  }

  void _navigate(ShellSection section) {
    setState(() {
      _section = section;
      _openApp = null;
    });
  }

  void _open(String appName) {
    if (appName == 'Settings') {
      _navigate(ShellSection.settings);
      return;
    }
    if (MediaQuery.sizeOf(context).width >= 820) {
      setState(() {
        _openApp = null;
        _section = ShellSection.home;
        final index = _windows.indexWhere((window) => window.name == appName);
        if (index >= 0) {
          final window = _windows.removeAt(index)..minimized = false;
          _windows.add(window);
        } else {
          _windows.add(_DesktopWindow(name: appName, offset: _windows.length));
        }
      });
      return;
    }
    setState(() {
      _openApp = appName;
      _section = ShellSection.apps;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 820;
        final content = !desktop && _openApp != null
            ? ConoAppPage(
                name: _openApp!,
                preferences: widget.preferences,
                quota: _quota,
                browserController: _ladybirdController,
                onOpenWebsite: _openWebsite,
                onBack: () => setState(() => _openApp = null),
              )
            : _buildSection(context);

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (desktop) _desktopRail(context),
                Expanded(
                  child: Column(
                    children: [
                      _topBar(context, desktop),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, workArea) => Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onSecondaryTapUp: desktop
                                      ? (details) => _showDesktopContextMenu(
                                            details.globalPosition,
                                          )
                                      : null,
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1180,
                                      ),
                                      child: content,
                                    ),
                                  ),
                                ),
                              ),
                              if (desktop)
                                for (final window in _windows)
                                  _buildWindow(
                                    window,
                                    Size(workArea.maxWidth, workArea.maxHeight),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      if (desktop && _windows.isNotEmpty) _desktopTaskbar(),
                      if (!desktop && _openApp == null) _mobileNavigation(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDesktopContextMenu(Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'Cono AI',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 18),
              SizedBox(width: 10),
              Text('Cono AI'),
            ],
          ),
        ),
      ],
    );
    if (selected != null && mounted) {
      _open(selected);
    }
  }

  Widget _buildWindow(_DesktopWindow window, Size bounds) {
    final width =
        window.maximized ? bounds.width : math.min(window.width, bounds.width);
    final height = window.maximized
        ? bounds.height
        : math.min(window.height, bounds.height);
    final left = window.maximized
        ? 0.0
        : window.left
            .clamp(0.0, math.max(0.0, bounds.width - width))
            .toDouble();
    final top = window.maximized
        ? 0.0
        : window.top
            .clamp(0.0, math.max(0.0, bounds.height - height))
            .toDouble();

    return Positioned(
      key: ValueKey(window.name),
      left: left,
      top: top,
      width: width,
      height: height,
      child: Offstage(
        offstage: window.minimized,
        child: _ConoWindowFrame(
          title: window.name,
          maximized: window.maximized,
          onFocus: () => _focusWindow(window),
          onMove: (delta) => _moveWindow(window, delta, bounds),
          onResize: (delta) => _resizeWindow(window, delta, bounds),
          onMinimize: () => setState(() => window.minimized = true),
          onMaximize: () =>
              setState(() => window.maximized = !window.maximized),
          onClose: () => setState(() => _windows.remove(window)),
          child: ConoAppPage(
            name: window.name,
            preferences: widget.preferences,
            quota: _quota,
            browserController: _ladybirdController,
            onOpenWebsite: _openWebsite,
            embedded: true,
            onBack: () => setState(() => _windows.remove(window)),
          ),
        ),
      ),
    );
  }

  void _focusWindow(_DesktopWindow window) {
    if (_windows.isEmpty || identical(_windows.last, window)) {
      return;
    }
    setState(() {
      _windows
        ..remove(window)
        ..add(window);
    });
  }

  void _moveWindow(_DesktopWindow window, Offset delta, Size bounds) {
    if (window.maximized) {
      return;
    }
    setState(() {
      window.left = (window.left + delta.dx)
          .clamp(0.0, math.max(0.0, bounds.width - window.width))
          .toDouble();
      window.top = (window.top + delta.dy)
          .clamp(0.0, math.max(0.0, bounds.height - window.height))
          .toDouble();
    });
  }

  void _resizeWindow(_DesktopWindow window, Offset delta, Size bounds) {
    if (window.maximized) {
      return;
    }
    setState(() {
      final maxWidth = math.max(160.0, bounds.width - window.left);
      final maxHeight = math.max(140.0, bounds.height - window.top);
      window.width = (window.width + delta.dx)
          .clamp(math.min(320.0, maxWidth), maxWidth)
          .toDouble();
      window.height = (window.height + delta.dy)
          .clamp(math.min(240.0, maxHeight), maxHeight)
          .toDouble();
    });
  }

  Widget _desktopTaskbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final window in _windows)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => window.minimized = false);
                    _focusWindow(window);
                  },
                  icon: Icon(
                    window.minimized ? Icons.web_asset_off : Icons.web_asset,
                    size: 16,
                  ),
                  label: Text(window.name),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _desktopRail(BuildContext context) {
    return Container(
      width: 88,
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: _glassDecoration(context, radius: 30),
      child: Column(
        children: [
          const _BrandMark(size: 42),
          const SizedBox(height: 32),
          for (final section in ShellSection.values)
            _RailButton(
              section: section,
              selected: _openApp == null && _section == section,
              onTap: () => _navigate(section),
            ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, bool desktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 18 : 20, 12, 20, 6),
      child: Row(
        children: [
          if (!desktop) ...[
            const _BrandMark(size: 34),
            const SizedBox(width: 11),
          ],
          Text(
            'CONO OS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          Text(
            _clockLabel(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.circle,
            size: 9,
            color: Colors.white.withOpacity(0.75),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    switch (_section) {
      case ShellSection.home:
        return _home(context);
      case ShellSection.duo:
        return _duo(context);
      case ShellSection.search:
        return _search(context);
      case ShellSection.apps:
        return _appGrid(context);
      case ShellSection.settings:
        return _settings(context);
    }
  }

  Widget _home(BuildContext context) {
    final greeting = _greeting();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 2.4,
                  color: Colors.white60,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'What are you working on?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                ),
          ),
          const SizedBox(height: 28),
          _HomeSearch(
            initialValue: _searchQuery,
            onChanged: (value) => _searchQuery = value,
            onSubmitted: (value) {
              setState(() {
                _searchQuery = value;
                _section = ShellSection.search;
              });
            },
          ),
          const SizedBox(height: 32),
          _sectionHeading(context, 'Favourites', action: 'All apps',
              onAction: () {
            _navigate(ShellSection.apps);
          }),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _apps
                .take(4)
                .map(
                  (app) => SizedBox(
                    width: 156,
                    child: _AppTile(app: app, onTap: () => _open(app.name)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          _GlassPanel(
            child: Row(
              children: [
                const _BrandMark(size: 46),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Meet Cono'),
                      SizedBox(height: 4),
                      Text(
                        'A small assistant that works on this device.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open Cono AI',
                  onPressed: () => _open('Cono AI'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appGrid(BuildContext context) {
    final query = _searchQuery.toLowerCase().trim();
    final visibleApps = _apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(query) ||
              app.description.toLowerCase().contains(query),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Apps', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'Your workspace, with room to grow.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: visibleApps
                .map(
                  (app) => SizedBox(
                    width: 190,
                    child: _AppTile(app: app, onTap: () => _open(app.name)),
                  ),
                )
                .toList(),
          ),
          if (visibleApps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('No apps match this search.'),
            ),
        ],
      ),
    );
  }

  Widget _search(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final matches = _apps
        .where(
          (app) =>
              query.isEmpty ||
              app.name.toLowerCase().contains(query) ||
              app.description.toLowerCase().contains(query),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          _HomeSearch(
            initialValue: _searchQuery,
            onChanged: (value) => setState(() => _searchQuery = value),
            onSubmitted: (value) => setState(() => _searchQuery = value),
            autofocus: true,
          ),
          const SizedBox(height: 24),
          Text(
            query.isEmpty ? 'Apps and actions' : 'Results',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final app in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AppTile(
                app: app,
                horizontal: true,
                onTap: () => _open(app.name),
              ),
            ),
          if (matches.isEmpty)
            const Text(
              'Nothing found yet. ConoOS search currently covers built-in apps only.',
              style: TextStyle(color: Colors.white60),
            ),
        ],
      ),
    );
  }

  Widget _duo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DUO', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'Choose two built-in apps and use them together.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DuoWorkspace(
              preferences: widget.preferences,
              onOpenWebsite: _openWebsite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'A simple, private workspace running inside your current OS.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 24),
        const _SettingRow(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          detail: 'Dark glass · simplified effects',
        ),
        const _SettingRow(
          icon: Icons.lock_outline,
          title: 'Privacy',
          detail: 'Cono AI runs locally; no chat is sent to a service.',
        ),
        const _SettingRow(
          icon: Icons.storage_outlined,
          title: 'Storage',
          detail: 'Notes are kept in app preferences on this device.',
        ),
        const _SettingRow(
          icon: Icons.info_outline,
          title: 'About ConoOS',
          detail: 'Early prototype · built-in apps are still in development.',
        ),
      ],
    );
  }

  Widget _mobileNavigation() {
    const sections = ShellSection.values;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: _glassDecoration(context, radius: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: sections
            .map(
              (section) => _MobileNavButton(
                section: section,
                selected: _section == section,
                onTap: () => _navigate(section),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DesktopWindow {
  _DesktopWindow({required this.name, required int offset})
      : left = 28.0 + offset.toDouble() * 24.0,
        top = 20.0 + offset.toDouble() * 22.0;

  final String name;
  double left;
  double top;
  double width = 560;
  double height = 440;
  bool maximized = false;
  bool minimized = false;
}

class _ConoWindowFrame extends StatelessWidget {
  const _ConoWindowFrame({
    required this.title,
    required this.maximized,
    required this.child,
    required this.onFocus,
    required this.onMove,
    required this.onResize,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
  });

  final String title;
  final bool maximized;
  final Widget child;
  final VoidCallback onFocus;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onFocus(),
      child: Material(
        color: const Color(0xFF101010),
        elevation: 22,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onFocus,
                  onPanUpdate: (details) => onMove(details.delta),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Minimize $title',
                          onPressed: onMinimize,
                          icon: const Icon(Icons.minimize, size: 18),
                        ),
                        IconButton(
                          tooltip:
                              maximized ? 'Restore $title' : 'Maximize $title',
                          onPressed: onMaximize,
                          icon: Icon(
                            maximized
                                ? Icons.filter_none_rounded
                                : Icons.crop_square_rounded,
                            size: 17,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close $title',
                          onPressed: onClose,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
            if (!maximized)
              Positioned(
                right: 2,
                bottom: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => onResize(details.delta),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ConoAppInfo {
  const ConoAppInfo(this.name, this.icon, this.description);

  final String name;
  final IconData icon;
  final String description;
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final ShellSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = _navigationItems[section]!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IconButton(
        tooltip: item.label,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? Colors.white.withOpacity(0.14) : Colors.transparent,
          foregroundColor: selected ? Colors.white : Colors.white60,
          minimumSize: const Size(54, 54),
        ),
        icon: Icon(item.icon),
      ),
    );
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final ShellSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = _navigationItems[section]!;
    return IconButton(
      tooltip: item.label,
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white54,
        backgroundColor:
            selected ? Colors.white.withOpacity(0.13) : Colors.transparent,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(item.icon),
    );
  }
}

class _HomeSearch extends StatefulWidget {
  const _HomeSearch({
    required this.initialValue,
    required this.onChanged,
    required this.onSubmitted,
    this.autofocus = false,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool autofocus;

  @override
  State<_HomeSearch> createState() => _HomeSearchState();
}

class _HomeSearchState extends State<_HomeSearch> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void didUpdateWidget(covariant _HomeSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search apps and settings...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: 'Search',
          onPressed: () => widget.onSubmitted(_controller.text),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.onTap,
    this.horizontal = false,
  });

  final ConoAppInfo app;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: horizontal
          ? Row(
              children: [
                _AppIcon(icon: app.icon, size: 44),
                const SizedBox(width: 14),
                Expanded(child: _appCopy(context)),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AppIcon(icon: app.icon, size: 48),
                const SizedBox(height: 22),
                _appCopy(context),
              ],
            ),
    );
  }

  Widget _appCopy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(app.name, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          app.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Icon(Icons.blur_circular, size: size * 0.54, color: Colors.white),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: _glassDecoration(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _navigationItems = <ShellSection, _NavigationItem>{
  ShellSection.home: _NavigationItem('Home', Icons.home_outlined),
  ShellSection.duo: _NavigationItem('DUO', Icons.splitscreen_rounded),
  ShellSection.search: _NavigationItem('Search', Icons.search_rounded),
  ShellSection.apps: _NavigationItem('Apps', Icons.grid_view_rounded),
  ShellSection.settings: _NavigationItem('Settings', Icons.tune),
};

BoxDecoration _glassDecoration(BuildContext context, {double radius = 26}) =>
    BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.76),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.24),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );

Widget _sectionHeading(
  BuildContext context,
  String label, {
  required String action,
  required VoidCallback onAction,
}) {
  return Row(
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const Spacer(),
      TextButton(onPressed: onAction, child: Text(action)),
    ],
  );
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) {
    return 'Good morning';
  }
  if (hour < 18) {
    return 'Good afternoon';
  }
  return 'Good evening';
}

String _clockLabel() {
  final now = TimeOfDay.now();
  final hour = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
  return '$hour:${now.minute.toString().padLeft(2, '0')}';
}
