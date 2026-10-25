import 'package:flutter/material.dart';

import '../../data/models/profile.dart';
import '../profile/profile_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.soon);
  final String label;
  final IconData icon;
  final String soon;
}

const _profileTab = _Tab('Perfil', Icons.person_rounded, '');

const _tabsByRole = {
  UserRole.owner: [
    _Tab('Explorar', Icons.map_rounded, 'El mapa de cuidadores llega pronto.'),
    _Tab('Reservas', Icons.event_note_rounded, 'Tus reservas aparecerán aquí.'),
    _Tab('Perros', Icons.pets_rounded, 'Registra a tus perros aquí.'),
    _profileTab,
  ],
  UserRole.sitter: [
    _Tab('Solicitudes', Icons.inbox_rounded, 'Aquí llegarán las solicitudes.'),
    _Tab('Agenda', Icons.calendar_month_rounded, 'Tu agenda aparecerá aquí.'),
    _Tab('Servicios', Icons.sell_rounded, 'Define tus servicios y precios.'),
    _profileTab,
  ],
  UserRole.admin: [
    _Tab('Aprobaciones', Icons.verified_user_rounded, 'Cuidadores por aprobar.'),
    _Tab('Reportes', Icons.flag_rounded, 'Reportes de usuarios.'),
    _Tab('Usuarios', Icons.group_rounded, 'Gestión de usuarios.'),
    _profileTab,
  ],
  UserRole.superadmin: [
    _Tab('Aprobaciones', Icons.verified_user_rounded, 'Cuidadores por aprobar.'),
    _Tab('Reportes', Icons.flag_rounded, 'Reportes de usuarios.'),
    _Tab('Usuarios', Icons.group_rounded, 'Gestión de usuarios.'),
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
  Widget build(BuildContext context) {
    final tabs = _tabsByRole[widget.profile.role]!;
    final index = _index.clamp(0, tabs.length - 1);
    final tab = tabs[index];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: tab == _profileTab
                ? ProfileScreen(profile: widget.profile)
                : _ComingSoon(tab: tab),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
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
            Icon(tab.icon, size: 56, color: Theme.of(context).colorScheme.primary),
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
