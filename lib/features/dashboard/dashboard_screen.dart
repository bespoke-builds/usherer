import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'dashboard_controller.dart';
import 'models/dashboard_list_item.dart';
import 'widgets/vehicle_chunk_card.dart';
import '../settings/settings_screen.dart';
import '../../data/models/tourist_group.dart';
import '../../data/local/hive_cache.dart';
import '../../app_config.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DashboardController _controller;
  bool _isAdmin = false;
  final _storage = const FlutterSecureStorage();
  final Map<String, GlobalKey> _touristKeys = {};
  final Map<String, GlobalKey<VehicleChunkCardState>> _groupCardKeys = {};
  String? _highlightedTouristId;
  final ScrollController _scrollController = ScrollController();

  Future<void> _checkAdminStatus() async {
    final status = await _storage.read(key: 'isAdmin') == 'true';
    if (mounted) {
      setState(() {
        _isAdmin = status;
      });
    }
  }

  double _estimateScrollOffset(String groupId) {
    double offset = 0.0;
    for (final item in _controller.listItems) {
      if (item is GroupCardItem && item.group.id == groupId) {
        break;
      }
      if (item is TimeHeaderItem) {
        offset += 50.0; // Header height including padding
      } else if (item is GroupCardItem) {
        offset += 160.0; // Unexpanded card height + vertical margin
      }
    }
    return offset;
  }

  void _scrollToTourist(String groupId, String touristId) {
    // Give time for SearchAnchor/keyboard transitions to fully complete first!
    Future.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted) return;

      var cardKey = _groupCardKeys[groupId];
      
      // If card key or context is null, scroll to estimated position first to force rendering
      if (cardKey == null || cardKey.currentContext == null) {
        final estOffset = _estimateScrollOffset(groupId);
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            estOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          // Wait a tiny bit for the item to render after scroll
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        // RE-FETCH the key now that the list item has built!
        cardKey = _groupCardKeys[groupId];
      }

      if (!mounted) return;

      // Step 1: Expand the card via its state
      cardKey?.currentState?.expand();

      // Step 2: After one frame, scroll precisely to the group card
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Re-fetch just in case it mounted in the current frame
        cardKey ??= _groupCardKeys[groupId];
        
        if (cardKey != null && cardKey!.currentContext != null) {
          Scrollable.ensureVisible(
            cardKey!.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.0,
          );
        }

        // Step 3: Wait for the AnimatedCrossFade animation (200ms) + buffer, then scroll to tourist
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          final touristKey = _touristKeys[touristId];
          if (touristKey != null && touristKey.currentContext != null) {
            Scrollable.ensureVisible(
              touristKey.currentContext!,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
              alignment: 0.5,
          );
        }

        // Step 4: Wait for the 500ms scroll animation to complete, THEN trigger the ripple highlight!
        Future.delayed(const Duration(milliseconds: 550), () {
          if (!mounted) return;
          setState(() {
            _highlightedTouristId = touristId;
          });

          // Step 5: After showing the gorgeous double ripple pulse for 2.4s, reset the highlight state
          Future.delayed(const Duration(milliseconds: 2400), () {
            if (mounted) {
              setState(() {
                if (_highlightedTouristId == touristId) {
                  _highlightedTouristId = null;
                }
              });
            }
          });
        });
      });
    });
  });
}


  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    final todayStr = _getTodayFormatted();
    final cachedDate = HiveCache.getCurrentDate(todayStr);

    String initialDate = todayStr;
    try {
      final cachedDateTime = _parseSheetDate(cachedDate);
      final todayDateTime = _parseSheetDate(todayStr);

      final cachedDayOnly = DateTime(
        cachedDateTime.year,
        cachedDateTime.month,
        cachedDateTime.day,
      );
      final todayDayOnly = DateTime(
        todayDateTime.year,
        todayDateTime.month,
        todayDateTime.day,
      );

      if (cachedDayOnly.isBefore(todayDayOnly)) {
        initialDate = todayStr;
        HiveCache.setCurrentDate(todayStr);
      } else {
        initialDate = cachedDate;
      }
    } catch (_) {
      initialDate = todayStr;
    }

    _controller = DashboardController(initialDate: initialDate);
  }

  String _getTodayFormatted() {
    final now = DateTime.now();
    // Custom date format "11TH MAY" or simple fallback
    final monthNames = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUNE',
      'JULY',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final monthStr = monthNames[now.month - 1];

    String suffix = 'TH';
    final day = now.day;
    if (day >= 11 && day <= 13) {
      suffix = 'TH';
    } else {
      switch (day % 10) {
        case 1:
          suffix = 'ST';
          break;
        case 2:
          suffix = 'ND';
          break;
        case 3:
          suffix = 'RD';
          break;
        default:
          suffix = 'TH';
          break;
      }
    }
    return '$day$suffix $monthStr';
  }

  DateTime _parseSheetDate(String dateStr) {
    try {
      final cleanStr = dateStr.trim().toUpperCase();
      final parts = cleanStr.split(' ');
      if (parts.length < 2) return DateTime.now();

      final dayStr = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
      final day = int.tryParse(dayStr) ?? 1;

      final monthNames = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      final monthStr = parts[1];
      final month = monthNames.indexWhere((m) => monthStr.startsWith(m)) + 1;
      if (month == 0) return DateTime.now();

      final year = DateTime.now().year;
      return DateTime(year, month, day);
    } catch (e) {
      return DateTime.now();
    }
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final initialDate = _parseSheetDate(_controller.date);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.surfaceHigh,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final formatted = _formatSheetDate(pickedDate);
      _controller.changeDate(formatted);
    }
  }

  String _formatSheetDate(DateTime date) {
    final monthNames = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUNE',
      'JULY',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final monthStr = monthNames[date.month - 1];

    String suffix = 'TH';
    final day = date.day;
    if (day >= 11 && day <= 13) {
      suffix = 'TH';
    } else {
      switch (day % 10) {
        case 1:
          suffix = 'ST';
          break;
        case 2:
          suffix = 'ND';
          break;
        case 3:
          suffix = 'RD';
          break;
        default:
          suffix = 'TH';
          break;
      }
    }
    return '$day$suffix $monthStr';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final totalExp = _controller.totalExpected;
        final totalArr = _controller.totalArrived;
        final progressRatio = totalExp > 0 ? totalArr / totalExp : 0.0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            scrolledUnderElevation: 0,
            title: Row(
              children: [
                Image.asset(
                  'assets/icon.png',
                  height: 28,
                  width: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                Text(
                  'USHERER',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(
                    Icons.sync_rounded,
                    color: AppColors.textPrimary,
                    size: 26,
                  ),
                  onPressed: () async {
                    try {
                      await _controller.syncFromSheets();
                    } catch (e) {
                      if (context.mounted) {
                        String errorMsg = e.toString();
                        if (errorMsg.startsWith('Exception: ')) {
                          errorMsg = errorMsg.substring(11);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sync failed: $errorMsg'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              SearchAnchor(
                viewBackgroundColor: AppColors.surface,
                viewSurfaceTintColor: Colors.transparent,
                viewElevation: 0,
                viewHintText: 'Search tourist name...',
                headerTextStyle: AppTypography.bodyPrimary,
                headerHintStyle: AppTypography.bodySecondary,
                builder: (BuildContext context, SearchController controller) {
                  return IconButton(
                    icon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textPrimary,
                      size: 26,
                    ),
                    onPressed: () {
                      controller.openView();
                    },
                  );
                },
                suggestionsBuilder: (BuildContext context, SearchController controller) {
                  final String query = controller.text.toLowerCase();
                  final List<Widget> results = [];

                  for (final group in _controller.groups) {
                    for (final tourist in group.tourists) {
                      if (tourist.name.toLowerCase().contains(query)) {
                        results.add(
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                              child: Text(
                                tourist.name.isNotEmpty ? tourist.name[0].toUpperCase() : '',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              tourist.name,
                              style: AppTypography.bodyPrimary.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${group.vehicleType.toUpperCase()} (${group.numberPlate ?? "No Plate"}) • ${group.flightNumber}',
                              style: AppTypography.bodySecondary.copyWith(fontSize: 12),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            onTap: () {
                              controller.closeView(tourist.name);
                              _scrollToTourist(group.id, tourist.id);
                            },
                          ),
                        );
                      }
                    }
                  }

                  if (results.isEmpty) {
                    return [
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'No matching tourists found',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ];
                  }

                  return results;
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: AppColors.textPrimary,
                  size: 26,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                  _checkAdminStatus(); // Refresh admin state when settings screen pops back
                  _controller.refreshSubscription(); // Reactively refresh data stream
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
  
                  // Date Header & Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showDatePicker(context),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _controller.date.toUpperCase(),
                                  style: AppTypography.displayHeader,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.accent,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_controller.totalPickedUp} P / ${_controller.totalDroppedOff} D OF $totalExp',
                            style: AppTypography.labelChip.copyWith(
                              color: AppColors.accent,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PICKUP / DROPOFF STAGES',
                            style: AppTypography.bodySecondary.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
  
                  // Animated Progress Bar (thin with coral fill)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 6,
                      color: AppColors.border,
                      child: Stack(
                        children: [
                          AnimatedFractionallySizedBox(
                            widthFactor: progressRatio.clamp(0.0, 1.0),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
  
                  // Groups ListView
                  Expanded(
                    child: Stack(
                      children: [
                        _controller.groups.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      AppConfig.spreadsheetId == null ||
                                              AppConfig.spreadsheetId!.isEmpty
                                          ? Icons.link_off_outlined
                                          : Icons.inbox_outlined,
                                      color: AppColors.textSecondary.withValues(
                                        alpha: 0.3,
                                      ),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      AppConfig.spreadsheetId == null ||
                                              AppConfig.spreadsheetId!.isEmpty
                                          ? 'No Sheet Configured'
                                          : 'No Groups Synchronized',
                                      style: AppTypography.titleMedium.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppConfig.spreadsheetId == null ||
                                              AppConfig.spreadsheetId!.isEmpty
                                          ? 'Go to Settings to set up your Google Sheet.'
                                          : 'Tap the sync button or pick another date.',
                                      style: AppTypography.bodySecondary,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : CustomScrollView(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                cacheExtent: 600,
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    sliver: SliverList.builder(
                                      itemCount: _controller.listItems.length,
                                      itemBuilder: (context, index) {
                                        final item = _controller.listItems[index];
                                        return switch (item) {
                                          TimeHeaderItem() => _buildTimeHeader(item),
                                          GroupCardItem() => _buildGroupCard(item.group),
                                        };
                                      },
                                    ),
                                  ),
                                ],
                              ),
  
                        // Premium glassmorphism blur overlay during background sync / loading
                        if (_controller.isLoading)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 3.5,
                                  sigmaY: 3.5,
                                ),
                                child: Container(
                                  color: AppColors.background.withValues(
                                    alpha: 0.35,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.accent,
                                      strokeWidth: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeHeader(TimeHeaderItem item) {
    return Padding(
      padding: EdgeInsets.only(
        top: item.isFirst ? 8.0 : 20.0,
        bottom: 8.0,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: AppColors.accent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            item.timeStr.toUpperCase(),
            style: AppTypography.labelChip.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Divider(
              color: AppColors.border,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(TouristGroup group) {
    final groupKey = _groupCardKeys.putIfAbsent(
      group.id,
      () => GlobalKey<VehicleChunkCardState>(),
    );
    return VehicleChunkCard(
      key: groupKey,
      group: group,
      touristKeys: _touristKeys,
      highlightedTouristId: _highlightedTouristId,
      onTouristStatusChanged: (touristId, field, value) {
        _controller.markTouristStatus(
          groupId: group.id,
          touristId: touristId,
          field: field,
          value: value,
        );
      },
      onTouristNoteChanged: (touristId, note) {
        _controller.updateTouristNote(
          groupId: group.id,
          touristId: touristId,
          note: note,
        );
      },
    );
  }
}
