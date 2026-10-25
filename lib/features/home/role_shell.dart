import 'package:flutter/material.dart';

import '../../data/models/profile.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/doggo_logo.dart';
import '../admin/approvals_tab.dart';
import '../admin/reports_tab.dart';
import '../admin/users_tab.dart';
import '../bookings/owner_bookings_tab.dart';
import '../dogs/dogs_tab.dart';
import '../map/map_screen.dart';
import '../sitter_dashboard/agenda_tab.dart';
import '../sitter_dashboard/requests_tab.dart';
import '../sitter_dashboard/services_tab.dart';
import '../profile/profile_screen.dart';

/// Ancho desde el cual la navegación pasa de barra inferior a riel lateral.
const wideBreakpoint = 840.0;

class _Tab {
  const _Tab(
    this.label,
    this.icon,
    this.soon, {
    this.builder,
    this.fullBleed = false,
  });
  final String label;
  final IconData icon;
  final String soon;

  /// Pantalla real de la pestaña; sin ella se muestra "llega pronto".
  final WidgetBuilder? builder;

  /// Ocupa todo el ancho (el mapa) en vez de centrarse con ancho máximo.
  final bool fullBleed;
}

Widget _mapTab(BuildContext context) => const MapScreen();
Widget _requestsTab(BuildContext context) => const RequestsTab();
Widget _ownerBookingsTab(BuildContext context) => const OwnerBookingsTab();
Widget _dogsTab(BuildContext context) => const DogsTab();
Widget _approvalsTab(BuildContext context) => const ApprovalsTab();
Widget _reportsTab(BuildContext context) => const ReportsTab();
Widget _usersTab(BuildContext context) => const UsersTab();
Widget _agendaTab(BuildContext context) => const AgendaTab();
Widget _servicesTab(BuildContext context) => const ServicesTab();

const _profileTab = _Tab('Perfil', Icons.person_rounded, '');

const _tabsByRole = {
  UserRole.owner: [
    _Tab('Explorar', Icons.map_rounded, '', builder: _mapTab, fullBleed: true),
    _Tab('Reservas', Icons.event_note_rounded, '', builder: _ownerBookingsTab),
    _Tab('Perros', Icons.pets_rounded, '', builder: _dogsTab),
    _profileTab,
  ],
  UserRole.sitter: [
    _Tab('Solicitudes', Icons.inbox_rounded, '', builder: _requestsTab),
    _Tab('Agenda', Icons.calendar_month_rounded, '', builder: _agendaTab),
    _Tab('Servicios', Icons.sell_rounded, '', builder: _servicesTab),
    _profileTab,
  ],
  UserRole.admin: [
    _Tab(
      'Aprobaciones',
      Icons.verified_user_rounded,
      '',
      builder: _approvalsTab,
    ),
    _Tab('Reportes', Icons.flag_rounded, '', builder: _reportsTab),
    _Tab('Usuarios', Icons.group_rounded, '', builder: _usersTab),
    _profileTab,
  ],
  UserRole.superadmin: [
    _Tab(
      'Aprobaciones',
      Icons.verified_user_rounded,
      '',
      builder: _approvalsTab,
    ),
    _Tab('Reportes', Icons.flag_rounded, '', builder: _reportsTab),
    _Tab('Usuarios', Icons.group_rounded, '', builder: _usersTab),
    _Tab('Equipo', Icons.shield_rounded, 'Gobierno del equipo de admins.'),
    _profileTab,
  ],
};

/// Navegación inferior según el rol. Las pestañas se irán llenando por fase.
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.profile});

  final Profile profile;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Al entrar con otra cuenta, los avisos de la anterior no deben seguir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabsByRole[widget.profile.role]!;
    final index = _index.clamp(0, tabs.length - 1);
    final tab = tabs[index];
    final Widget body = tab == _profileTab
        ? ProfileScreen(profile: widget.profile)
        : tab.builder != null
        ? tab.builder!(context)
        : _ComingSoon(tab: tab);
    final content = tab.fullBleed
        ? body
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: body,
            ),
          );

    // Pantallas anchas (escritorio, tablet horizontal): riel lateral.
    // Pantallas angostas (celular): barra inferior.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideBreakpoint) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: AppColors.background,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: DoggoLogo(size: 56),
                    ),
                    destinations: [
                      for (final t in tabs)
                        NavigationRailDestination(
                          icon: Icon(t.icon),
                          label: Text(t.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: SafeArea(child: content),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in tabs)
                NavigationDestination(icon: Icon(t.icon), label: t.label),
            ],
          ),
        );
      },
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.tab});

  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              tab.soon,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
