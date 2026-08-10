import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/order_providers.dart';
import '../../widgets/app_state_widgets.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _errorMessage(Object? error) {
    final message = error?.toString() ?? '';

    if (AppErrorHandler.isPermissionDenied(error)) {
      return 'Unable to load orders';
    }

    if (message.contains('failed-precondition') ||
        message.toLowerCase().contains('index')) {
      return 'Orders need a Firestore index. Check debug console.';
    }

    return 'Unable to load orders';
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Orders')),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('Admin access required'),
        ),
      );
    }

    final ordersAsync = ref.watch(adminOrderListProvider);
    final pendingStatusUpdates = ref.watch(orderStatusUpdateControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Admin Orders')),
      body: ordersAsync.when(
        data: (state) {
          final orders = state.orders;

          return Column(
            children: [
              _DateOrderControls(
                controller: _searchController,
                isSearching: state.searchQuery.isNotEmpty,
                statusFilter: state.statusFilter,
                sortAscending: state.sortAscending,
                onSearchChanged: _onSearchChanged,
                onClearSearch: _clearSearch,
                onStatusChanged: (status) {
                  ref.read(adminOrderListProvider.notifier).setStatusFilter(
                        status,
                      );
                },
                onSortChanged: (sortAscending) {
                  ref.read(adminOrderListProvider.notifier).setSortAscending(
                        sortAscending,
                      );
                },
              ),
              Expanded(
                child: orders.isEmpty
                    ? _AdminOrdersEmptyState(searchQuery: state.searchQuery)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: orders.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= orders.length) {
                            return _AdminOrderListFooter(
                              isLoading: state.isLoadingMore,
                              hasMore: state.hasMore,
                              onLoadMore: () => _loadMore(context, ref),
                            );
                          }

                          final order = orders[index];
                          final effectiveStatus =
                              pendingStatusUpdates[order.id] ??
                                  OrderStatus.normalize(order.status);
                          final isUpdating =
                              pendingStatusUpdates.containsKey(order.id);

                          return _AdminOrderCard(
                            order: order,
                            effectiveStatus: effectiveStatus,
                            isUpdating: isUpdating,
                            onStatusChanged: (status) async {
                              try {
                                await ref
                                    .read(
                                      orderStatusUpdateControllerProvider
                                          .notifier,
                                    )
                                    .updateOrderStatus(
                                      orderId: order.id,
                                      status: status,
                                      targetUserId: order.userId,
                                    );
                                ref
                                    .read(adminOrderListProvider.notifier)
                                    .loadInitial();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      AdminOrdersText.statusUpdateSuccess,
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) return;

                                AppErrorHandler.showErrorSnackBar(
                                  context,
                                  error,
                                  fallbackMessage:
                                      'Unable to update order status',
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: _errorMessage(error),
          message: AppErrorHandler.messageFor(
            error,
            fallback: 'Please try again in a moment.',
          ),
          onRetry: () {
            ref.read(adminOrderListProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(adminOrderListProvider.notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;

      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Unable to load more orders',
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(adminOrderListProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(adminOrderListProvider.notifier).search('');
  }
}

class AdminDateOrdersScreen extends ConsumerStatefulWidget {
  const AdminDateOrdersScreen({
    super.key,
    required this.date,
  });

  final DateTime date;

  @override
  ConsumerState<AdminDateOrdersScreen> createState() {
    return _AdminDateOrdersScreenState();
  }
}

class _AdminDateOrdersScreenState extends ConsumerState<AdminDateOrdersScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  DateTime get _date => _dateOnly(widget.date);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Date Orders')),
        body: Center(
          child: isAdminAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('Admin access required'),
        ),
      );
    }

    final listProvider = adminDateOrderListProvider(_date);
    final ordersAsync = ref.watch(listProvider);
    final pendingStatusUpdates = ref.watch(orderStatusUpdateControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Orders - ${_formatDateOnly(_date)}')),
      body: ordersAsync.when(
        data: (state) {
          final orders = state.orders;

          return Column(
            children: [
              _DateOrderControls(
                controller: _searchController,
                isSearching: state.searchQuery.isNotEmpty,
                statusFilter: state.statusFilter,
                sortAscending: state.sortAscending,
                onSearchChanged: _onSearchChanged,
                onClearSearch: _clearSearch,
                onStatusChanged: (status) {
                  ref.read(listProvider.notifier).setStatusFilter(status);
                },
                onSortChanged: (sortAscending) {
                  ref.read(listProvider.notifier).setSortAscending(
                        sortAscending,
                      );
                },
              ),
              Expanded(
                child: orders.isEmpty
                    ? _AdminOrdersEmptyState(searchQuery: state.searchQuery)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: orders.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= orders.length) {
                            return _AdminOrderListFooter(
                              isLoading: state.isLoadingMore,
                              hasMore: state.hasMore,
                              onLoadMore: () => _loadMore(context),
                            );
                          }

                          final order = orders[index];
                          final effectiveStatus =
                              pendingStatusUpdates[order.id] ??
                                  OrderStatus.normalize(order.status);
                          final isUpdating =
                              pendingStatusUpdates.containsKey(order.id);

                          return _AdminOrderCard(
                            order: order,
                            effectiveStatus: effectiveStatus,
                            isUpdating: isUpdating,
                            onStatusChanged: (status) async {
                              try {
                                await ref
                                    .read(
                                      orderStatusUpdateControllerProvider
                                          .notifier,
                                    )
                                    .updateOrderStatus(
                                      orderId: order.id,
                                      status: status,
                                      targetUserId: order.userId,
                                    );
                                await ref
                                    .read(listProvider.notifier)
                                    .loadInitial();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      AdminOrdersText.statusUpdateSuccess,
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                AppErrorHandler.showErrorSnackBar(
                                  context,
                                  error,
                                  fallbackMessage:
                                      'Unable to update order status',
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load date orders',
          message: AppErrorHandler.messageFor(
            error,
            fallback: 'Please try again in a moment.',
          ),
          onRetry: () {
            ref.read(listProvider.notifier).loadInitial();
          },
        ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context) async {
    try {
      final listProvider = adminDateOrderListProvider(_date);
      await ref.read(listProvider.notifier).loadNext();
    } catch (error) {
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        error,
        fallbackMessage: 'Unable to load more orders',
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final listProvider = adminDateOrderListProvider(_date);
      ref.read(listProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    final listProvider = adminDateOrderListProvider(_date);
    ref.read(listProvider.notifier).search('');
  }
}

class AdminOrdersText {
  const AdminOrdersText._();

  static const statusUpdateSuccess = 'Order status updated';
  static const searchHint = 'Search by order ID, customer, or phone';
}

class _AdminOrdersEmptyState extends StatelessWidget {
  const _AdminOrdersEmptyState({required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final isSearching = searchQuery.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          isSearching ? 'No matching orders found' : 'No orders yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DateOrderControls extends StatelessWidget {
  const _DateOrderControls({
    required this.controller,
    required this.isSearching,
    required this.statusFilter,
    required this.sortAscending,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final bool isSearching;
  final String statusFilter;
  final bool sortAscending;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<bool> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final selectedStatus = statusFilter.trim().isEmpty
        ? 'All'
        : OrderStatus.normalize(statusFilter);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: AdminOrdersText.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: isSearching
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final filters = [
                SizedBox(
                  width: constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'All', child: Text('All')),
                      for (final status in OrderStatus.values)
                        DropdownMenuItem(value: status, child: Text(status)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      onStatusChanged(value == 'All' ? '' : value);
                    },
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.south_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Newest'),
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.north_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Oldest'),
                        ),
                      ),
                    ],
                    selected: {sortAscending},
                    onSelectionChanged: (values) {
                      onSortChanged(values.first);
                    },
                  ),
                ),
              ];

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: filters,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminOrderListFooter extends StatelessWidget {
  const _AdminOrderListFooter({
    required this.isLoading,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!hasMore) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'All loaded orders are visible',
            style: TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Center(
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text('Load more'),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.effectiveStatus,
    required this.isUpdating,
    required this.onStatusChanged,
  });

  final Order order;
  final String effectiveStatus;
  final bool isUpdating;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _OrderStatusStyle.resolve(effectiveStatus);
    final orderDate = order.createdAt == null
        ? 'Date not available'
        : _formatDate(order.createdAt!);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _OrderIdBlock(orderId: order.displayId)),
                  const SizedBox(width: 12),
                  _StatusChip(
                    label: effectiveStatus,
                    style: statusStyle,
                    isUpdating: isUpdating,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _OrderSummaryLine(
                customerName: order.customerDisplayName,
                phone: _fallback(order.phone, 'Phone not available'),
                total: '\u20B9${_formatPrice(order.total)}',
                orderDate: orderDate,
              ),
            ],
          ),
          children: [
            if (effectiveStatus == 'Failed' && order.failureReason != null && order.failureReason!.isNotEmpty) ...[
              _InfoBlock(
                label: 'Failure Reason',
                value: order.failureReason!,
                icon: Icons.error_outline_rounded,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
            ],
            _ExpandedInfoSection(
              title: 'Products',
              icon: Icons.shopping_bag_outlined,
              child: _OrderProductList(items: order.items),
            ),
            const SizedBox(height: 12),
            _InfoGrid(
              entries: [
                _InfoEntry(
                  label: 'Customer phone',
                  value: _fallback(order.phone, 'Phone not available'),
                  icon: Icons.phone_outlined,
                ),
                _InfoEntry(
                  label: 'Payment method',
                  value: _fallback(order.paymentMethod, 'COD'),
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoBlock(
              label: 'Delivery address',
              value: _fallback(
                [
                  order.address.trim(),
                  if (order.pincode.trim().isNotEmpty) 'Pincode: ${order.pincode.trim()}',
                ].where((s) => s.isNotEmpty).join('\n'),
                'No delivery address added',
              ),
              icon: Icons.location_on_outlined,
              maxLines: 6,
            ),
            const SizedBox(height: 12),
            _ExpandedInfoSection(
              title: 'Payment Details',
              icon: Icons.receipt_long_outlined,
              child: _PaymentBreakdown(order: order),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('status-${order.id}-$effectiveStatus'),
              initialValue: effectiveStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Update Order',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: OrderStatus.values.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(status),
                );
              }).toList(),
              onChanged: (isUpdating || effectiveStatus == OrderStatus.cancelled || effectiveStatus == OrderStatus.failed || effectiveStatus == 'Failed')
                  ? null
                  : (status) {
                      if (status == null || status == effectiveStatus) {
                        return;
                      }
                      onStatusChanged(status);
                    },
            ),
          ],
        ),
      ),
    );
  }

  String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _formatPrice(double price) {
    return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year} $hour:$minute';
  }
}

class _OrderSummaryLine extends StatelessWidget {
  const _OrderSummaryLine({
    required this.customerName,
    required this.phone,
    required this.total,
    required this.orderDate,
  });

  final String customerName;
  final String phone;
  final String total;
  final String orderDate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _SummaryPill(
          icon: Icons.person_outline_rounded,
          label: customerName,
        ),
        _SummaryPill(
          icon: Icons.phone_outlined,
          label: phone,
        ),
        _SummaryPill(
          icon: Icons.payments_outlined,
          label: total,
          isStrong: true,
        ),
        _SummaryPill(
          icon: Icons.calendar_today_rounded,
          label: orderDate,
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    this.isStrong = false,
  });

  final IconData icon;
  final String label;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedInfoSection extends StatelessWidget {
  const _ExpandedInfoSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _OrderProductList extends StatelessWidget {
  const _OrderProductList({required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No items',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < items.length; index += 1) ...[
          _OrderProductRow(item: items[index]),
          if (index != items.length - 1)
            const Divider(height: 18, color: AppColors.border),
        ],
      ],
    );
  }
}

class _OrderProductRow extends StatelessWidget {
  const _OrderProductRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.unit.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.unit,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${item.quantity} x \u20B9${_formatPrice(item.effectivePrice)}',
          style: const TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          label: 'Original amount',
          value: '\u20B9${_formatPrice(order.itemsAmount)}',
        ),
        if (order.productSavings > 0)
          _DetailRow(
            label: 'Product savings',
            value: '-\u20B9${_formatPrice(order.productSavings)}',
            valueColor: AppColors.primary,
          ),
        _DetailRow(
          label: 'Cart discount',
          value: order.cartDiscount > 0
              ? '-\u20B9${_formatPrice(order.cartDiscount)}'
              : '\u20B90',
          valueColor: AppColors.primary,
        ),
        _DetailRow(
          label: 'Delivery fee',
          value: order.deliveryFee > 0
              ? '\u20B9${_formatPrice(order.deliveryFee)}'
              : 'Free',
          valueColor: order.deliveryFee > 0 ? null : AppColors.primary,
        ),
        const Divider(height: 18, color: AppColors.border),
        _DetailRow(
          label: 'Final payable',
          value: '\u20B9${_formatPrice(order.total)}',
          isStrong: true,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isStrong ? AppColors.text : AppColors.mutedText,
                fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPrice(double price) {
  return price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
}

DateTime _dateOnly(DateTime date) {
  final localDate = date.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day);
}

String _formatDateOnly(DateTime date) {
  final localDate = date.toLocal();
  final day = localDate.day.toString().padLeft(2, '0');
  final month = localDate.month.toString().padLeft(2, '0');
  return '$day/$month/${localDate.year}';
}

class _OrderIdBlock extends StatelessWidget {
  const _OrderIdBlock({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final visibleId = orderId.trim().isEmpty ? 'Unknown order' : orderId.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order ID',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            visibleId,
            maxLines: 2,
            style: const TextStyle(
              color: AppColors.text,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.entries});

  final List<_InfoEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 520;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: _InfoBlock(
                  label: entry.label,
                  value: entry.value,
                  icon: entry.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoEntry {
  const _InfoEntry({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
    required this.icon,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.style,
    required this.isUpdating,
  });

  final String label;
  final _OrderStatusStyle style;
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUpdating) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: style.foreground,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: style.foreground,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderStatusStyle {
  const _OrderStatusStyle({
    required this.foreground,
    required this.background,
  });

  final Color foreground;
  final Color background;

  static _OrderStatusStyle resolve(String status) {
    switch (OrderStatus.normalize(status)) {
      case OrderStatus.placed:
        return _OrderStatusStyle(
          foreground: AppColors.accent,
          background: AppColors.softOrange,
        );
      case OrderStatus.confirmed:
        return _OrderStatusStyle(
          foreground: AppColors.accent,
          background: AppColors.softOrange,
        );
      case OrderStatus.packed:
        return _OrderStatusStyle(
          foreground: AppColors.info,
          background: AppColors.info.withValues(alpha: 0.1),
        );
      case OrderStatus.outForDelivery:
        return _OrderStatusStyle(
          foreground: AppColors.accent,
          background: AppColors.softOrange,
        );
      case OrderStatus.delivered:
        return _OrderStatusStyle(
          foreground: AppColors.success,
          background: AppColors.softGreen,
        );
      case OrderStatus.cancelled:
        return _OrderStatusStyle(
          foreground: AppColors.danger,
          background: AppColors.danger.withValues(alpha: 0.1),
        );
      case OrderStatus.failed:
        return _OrderStatusStyle(
          foreground: AppColors.danger,
          background: AppColors.danger.withValues(alpha: 0.15),
        );
    }

    return _OrderStatusStyle(
      foreground: Colors.grey.shade800,
      background: Colors.grey.shade100,
    );
  }
}
