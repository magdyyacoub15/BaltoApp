import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../auth/domain/models/clinic_group.dart';
import '../domain/models/medical_record.dart';
import '../domain/patient.dart';
import 'package:intl/intl.dart';

class PrescriptionService {
  static Future<Uint8List> generatePrescriptionPdf({
    required ClinicGroup clinic,
    required Patient patient,
    required MedicalRecord record,
    required String languageCode,
  }) async {
    final pdf = pw.Document();

    final font     = await PdfGoogleFonts.notoSansArabicRegular();
    final boldFont = await PdfGoogleFonts.notoSansArabicBold();
    final fallback = await PdfGoogleFonts.notoSansRegular();
    final iconFont = await PdfGoogleFonts.materialIcons();

    // ── Palette ───────────────────────────────────────────────────────────────
    const primary  = PdfColor.fromInt(0xFF0D2D5E); // Deep navy
    const accent   = PdfColor.fromInt(0xFFD4A017); // Medical gold
    const bg       = PdfColor.fromInt(0xFFF9FAFB); // Near white
    const divider  = PdfColor.fromInt(0xFFE2E8F0); // Soft gray
    const textMain = PdfColor.fromInt(0xFF1A202C);
    const textSub  = PdfColor.fromInt(0xFF718096);

    final isArabic = languageCode == 'ar';
    final dir      = isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final crossEnd = isArabic
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;

    String lbl(String ar, String en) => isArabic ? ar : en;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: pw.EdgeInsets.zero,
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.zero,
          theme: pw.ThemeData.withFont(
            base: font,
            bold: boldFont,
            fontFallback: [fallback],
          ),
          buildBackground: (ctx) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Container(color: PdfColors.white),
                ),
                pw.Center(
                  child: pw.Transform.rotate(
                    angle: -0.5,
                    child: pw.Text(
                      'Rx',
                      style: pw.TextStyle(
                        font: fallback,
                        fontSize: 140,
                        color: const PdfColor.fromInt(0x0A0D2D5E),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        build: (ctx) {
          return pw.Directionality(
            textDirection: dir,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                    // ────────────────────────────────────────────────── HEADER
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(24, 28, 24, 20),
                      color: primary,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: crossEnd,
                              children: [
                                pw.Text(
                                  clinic.doctorName ?? clinic.name,
                                  textDirection: dir,
                                  style: pw.TextStyle(
                                    color: PdfColors.white,
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if ((clinic.specialization ?? '').isNotEmpty)
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.only(top: 4),
                                    child: pw.Text(
                                      clinic.specialization!,
                                      textDirection: dir,
                                      style: const pw.TextStyle(
                                        color: accent, fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (clinic.doctorName != null &&
                                    clinic.name.isNotEmpty)
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.only(top: 3),
                                    child: pw.Text(
                                      clinic.name,
                                      textDirection: dir,
                                      style: const pw.TextStyle(
                                        color: PdfColor(1, 1, 1, 0.7), fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          // Gold medical emblem
                          pw.Container(
                            width: 52,
                            height: 52,
                            decoration: pw.BoxDecoration(
                              color: accent,
                              borderRadius: pw.BorderRadius.circular(10),
                            ),
                            child: pw.Center(
                              child: pw.Icon(
                                const pw.IconData(0xe548),
                                font: iconFont,
                                color: PdfColors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Gold accent strip
                    pw.Container(height: 4, color: accent),

                    // ──────────────────────────────────────── PATIENT INFO CARD
                    pw.Container(
                      margin: const pw.EdgeInsets.fromLTRB(20, 16, 20, 0),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: bg,
                        borderRadius: pw.BorderRadius.circular(10),
                        border: pw.Border.all(color: divider),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _infoCell(lbl('الاسم', 'Patient'),
                              patient.name, textSub, textMain, dir),
                          _vDivider(),
                          _infoCell(lbl('السن', 'Age'),
                              '${patient.age} ${lbl('سنة', 'yr')}',
                              textSub, textMain, dir),
                          _vDivider(),
                          _infoCell(lbl('التاريخ', 'Date'),
                              DateFormat('yyyy/MM/dd').format(record.date),
                              textSub, textMain, dir),
                          if (patient.phone.isNotEmpty) ...[
                            _vDivider(),
                            _infoCell(lbl('الهاتف', 'Phone'),
                                patient.phone, textSub, textMain, dir),
                          ],
                        ],
                      ),
                    ),

                    // ──────────────────────────────────────────────────── BODY
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            // Diagnosis block (optional)
                            if (record.diagnosis.isNotEmpty) ...[
                              _sectionHeader(lbl('التشخيص', 'Diagnosis'),
                                  accent, iconFont, 0xe873),
                              pw.SizedBox(height: 6),
                              pw.Container(
                                width: double.infinity,
                                padding: const pw.EdgeInsets.all(10),
                                decoration: pw.BoxDecoration(
                                  color: const PdfColor.fromInt(0xFFFFFBEB),
                                  borderRadius: pw.BorderRadius.circular(8),
                                  border: pw.Border.all(
                                    color: const PdfColor.fromInt(0xFFFBD38D),
                                  ),
                                ),
                                child: pw.Text(
                                  record.diagnosis,
                                  textDirection: dir,
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    color: const PdfColor.fromInt(0xFF744210),
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                              pw.SizedBox(height: 14),
                            ],

                            // Medications header
                            _sectionHeader(lbl('الأدوية', 'Medications'),
                                primary, iconFont, 0xe549),
                            pw.SizedBox(height: 10),

                            // Numbered medications list
                            pw.Expanded(
                              child: pw.ListView.builder(
                                itemCount: record.medications.length,
                                itemBuilder: (_, i) {
                                  final med = record.medications[i];
                                  return pw.Container(
                                    margin: const pw.EdgeInsets.only(bottom: 8),
                                    decoration: pw.BoxDecoration(
                                      color: PdfColors.white,
                                      borderRadius:
                                          pw.BorderRadius.circular(8),
                                      border: pw.Border.all(color: divider),
                                    ),
                                    child: pw.Row(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.stretch,
                                      children: [
                                        // Number badge
                                        pw.Container(
                                          width: 32,
                                          decoration: pw.BoxDecoration(
                                            color: primary,
                                            borderRadius:
                                                const pw.BorderRadius.only(
                                              topLeft: pw.Radius.circular(7),
                                              bottomLeft:
                                                  pw.Radius.circular(7),
                                            ),
                                          ),
                                          child: pw.Center(
                                            child: pw.Text(
                                              '${i + 1}',
                                              style: const pw.TextStyle(
                                                color: PdfColors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Med name + instructions
                                        pw.Expanded(
                                          child: pw.Padding(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8,
                                            ),
                                            child: pw.Column(
                                              crossAxisAlignment: crossEnd,
                                              children: [
                                                pw.Text(
                                                  med.name,
                                                  textDirection:
                                                      pw.TextDirection.ltr,
                                                  style: pw.TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        pw.FontWeight.bold,
                                                    color: textMain,
                                                  ),
                                                ),
                                                if (med.instructions.isNotEmpty)
                                                  pw.Padding(
                                                    padding:
                                                        const pw.EdgeInsets
                                                            .only(top: 4),
                                                    child: pw.Text(
                                                      med.instructions,
                                                      textDirection: dir,
                                                      style:
                                                          const pw.TextStyle(
                                                        fontSize: 11,
                                                        color: textSub,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ──────────────────────────────────────────────── FOOTER
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(20, 12, 20, 14),
                      decoration: const pw.BoxDecoration(
                        color: bg,
                        border: pw.Border(
                          top: pw.BorderSide(color: divider, width: 1.5),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: crossEnd,
                              children: [
                                if ((clinic.address ?? '').isNotEmpty)
                                  _footerLine(iconFont, 0xe0c8,
                                      clinic.address!, accent, textMain),
                                if ((clinic.phone ?? '').isNotEmpty)
                                  pw.Padding(
                                    padding:
                                        const pw.EdgeInsets.only(top: 5),
                                    child: _footerLine(
                                      iconFont, 0xe0b0,
                                      '${lbl('ت', 'Tel')}: ${clinic.phone}',
                                      accent, textMain,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          // QR code
                          pw.Column(
                            children: [
                              pw.Container(
                                width: 50,
                                height: 50,
                                padding: const pw.EdgeInsets.all(3),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  borderRadius: pw.BorderRadius.circular(6),
                                  border: pw.Border.all(color: divider),
                                ),
                                child: pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: clinic.id,
                                  color: primary,
                                  drawText: false,
                                ),
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                lbl('كود العيادة', 'Clinic ID'),
                                style: const pw.TextStyle(
                                  fontSize: 8, color: textSub,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          );
        },
      ),
    );

    return await pdf.save();
  }

  // ── Helper Widgets ──────────────────────────────────────────────────────────

  static pw.Widget _infoCell(
    String label,
    String value,
    PdfColor labelColor,
    PdfColor valueColor,
    pw.TextDirection dir,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label,
            textDirection: dir,
            style: pw.TextStyle(fontSize: 9, color: labelColor)),
        pw.SizedBox(height: 3),
        pw.Text(value,
            textDirection: dir,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            )),
      ],
    );
  }

  static pw.Widget _vDivider() => pw.Container(
        width: 1,
        height: 30,
        color: const PdfColor.fromInt(0xFFE2E8F0),
      );

  static pw.Widget _sectionHeader(
    String title,
    PdfColor color,
    pw.Font iconFont,
    int iconCode,
  ) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3,
          height: 16,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Icon(pw.IconData(iconCode), font: iconFont, color: color, size: 15),
        pw.SizedBox(width: 6),
        pw.Text(title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  static pw.Widget _footerLine(
    pw.Font iconFont,
    int iconCode,
    String text,
    PdfColor iconColor,
    PdfColor textColor,
  ) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Icon(pw.IconData(iconCode),
            font: iconFont, color: iconColor, size: 12),
        pw.SizedBox(width: 6),
        pw.Text(text, style: pw.TextStyle(fontSize: 10, color: textColor)),
      ],
    );
  }
}
