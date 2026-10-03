import '../models/app_data.dart';
import '../models/client.dart';

String normalizeClientEmail(String email) => email.trim().toLowerCase();

/// Keeps one client per normalized email and retargets appointments to it.
/// Returns true when duplicate client rows were removed.
bool deduplicateClientsByEmail(AppData data) {
  final byEmail = <String, Client>{};
  final duplicateIds = <String, String>{};
  for (final client in data.clients) {
    final email = normalizeClientEmail(client.email);
    if (email.isEmpty) continue;
    final keeper = byEmail[email];
    if (keeper == null) {
      byEmail[email] = client;
    } else {
      if (keeper.clientUserId.isEmpty && client.clientUserId.isNotEmpty) {
        keeper.clientUserId = client.clientUserId;
      }
      duplicateIds[client.id] = keeper.id;
    }
  }
  if (duplicateIds.isEmpty) return false;

  for (final appointment in data.appointments) {
    final replacement = duplicateIds[appointment.clientId];
    if (replacement != null) appointment.clientId = replacement;
  }
  data.clients.removeWhere((client) => duplicateIds.containsKey(client.id));
  return true;
}
