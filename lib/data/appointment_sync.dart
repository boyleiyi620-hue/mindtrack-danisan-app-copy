import '../models/appointment.dart';
import 'mindtrack_backend.dart';

/// Psikologun yerel takvim kaydı ile danışanın takip ettiği ortak Supabase
/// randevu satırı arasındaki bağı yönetir.
///
/// Ortak kayıt kimliği yerel not alanında `request:<uuid>` olarak saklanır.
/// Yerel ve bağımsız takvim kayıtları için bu yardımcı sessizce işlem yapmaz.
String? sharedAppointmentId(Appointment appointment) {
  final notes = appointment.notes;
  if (!notes.startsWith('request:')) return null;
  final id = notes.substring('request:'.length).trim();
  return id.isEmpty ? null : id;
}

Future<void> syncSharedAppointment(Appointment appointment) async {
  final sharedId = sharedAppointmentId(appointment);
  if (sharedId == null) return;

  final at = DateTime.tryParse('${appointment.date} ${appointment.time}:00');
  if (at == null) {
    throw BackendException('Randevu tarih veya saat bilgisi geçersiz.');
  }

  await MindTrackBackend.instance.updateSharedAppointment(
    sharedId,
    status: appointment.status,
    at: at,
    linkedAppointmentId: appointment.id,
  );
}
