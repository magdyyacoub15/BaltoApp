import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/appointment.dart';

final appointmentRepositoryProvider = Provider(
  (ref) => AppointmentRepository(),
);

class AppointmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of appointments for a specific clinic.
  // If [date] is provided, returns all appointments for that day.
  // If [startAfter] is provided, returns appointments after that timestamp.
  Stream<List<Appointment>> getAppointments(
    String clinicId, {
    DateTime? date,
    DateTime? startAfter,
  }) {
    final DateTime startThreshold;
    final DateTime? endThreshold;

    if (date != null) {
      startThreshold = DateTime(date.year, date.month, date.day);
      endThreshold = startThreshold.add(const Duration(days: 1));
    } else {
      startThreshold =
          startAfter ?? DateTime.now().subtract(const Duration(hours: 24));
      endThreshold = null;
    }

    return _firestore
        .collection('appointments')
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs
              .map((doc) => Appointment.fromMap(doc.data(), doc.id))
              .where((appt) {
                final isAfter =
                    appt.date.isAfter(startThreshold) ||
                    appt.date.isAtSameMomentAs(startThreshold);
                final isBefore =
                    endThreshold == null || appt.date.isBefore(endThreshold);
                return isAfter && isBefore;
              })
              .toList();
          docs.sort((a, b) {
            // Completed appointments go to the bottom
            if (a.isCompleted && !b.isCompleted) return 1;
            if (!a.isCompleted && b.isCompleted) return -1;

            // If both have the same completion status, sort by queueOrder
            if (a.queueOrder != b.queueOrder) {
              return a.queueOrder.compareTo(b.queueOrder);
            }

            // Fallback to chronological order
            return a.date.compareTo(b.date);
          });
          return docs;
        });
  }

  // Stream of future appointments (for reminders)
  Stream<List<Appointment>> getUpcomingAppointments(String clinicId) {
    final now = DateTime.now();

    return _firestore
        .collection('appointments')
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs
              .map((doc) => Appointment.fromMap(doc.data(), doc.id))
              .where((appt) => appt.date.isAfter(now))
              .toList();
          docs.sort((a, b) {
            if (a.isCompleted && !b.isCompleted) return 1;
            if (!a.isCompleted && b.isCompleted) return -1;
            if (a.queueOrder != b.queueOrder) {
              return a.queueOrder.compareTo(b.queueOrder);
            }
            return a.date.compareTo(b.date);
          });
          return docs;
        });
  }

  Future<void> addAppointment(Appointment appointment) async {
    await _firestore.collection('appointments').add(appointment.toMap());
  }

  Future<void> updateAppointment(Appointment appointment) async {
    await _firestore
        .collection('appointments')
        .doc(appointment.id)
        .update(appointment.toMap());
  }

  Future<void> updateQueueOrder(List<Appointment> appointments) async {
    final batch = _firestore.batch();
    for (final appt in appointments) {
      final docRef = _firestore.collection('appointments').doc(appt.id);
      batch.update(docRef, {'queueOrder': appt.queueOrder});
    }
    await batch.commit();
  }

  Future<void> deleteAppointment(String id) async {
    await _firestore.collection('appointments').doc(id).delete();
  }
}
