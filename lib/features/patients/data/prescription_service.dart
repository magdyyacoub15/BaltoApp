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
    final font = await PdfGoogleFonts.notoSansArabicRegular();
    final boldFont = await PdfGoogleFonts.notoSansArabicBold();
    final iconFont = await PdfGoogleFonts.materialIcons();
    final fallbackFont = await PdfGoogleFonts.notoSansRegular();

    final primaryColor = PdfColor.fromHex('#1A365D'); // Deep Navy Blue
    final accentColor = PdfColor.fromHex('#00B5D8'); // Vibrant Cyan
    final surfaceColor = PdfColor.fromHex('#F7FAFC'); // Very Light Blue/Gray
    final textDark = PdfColor.fromHex('#2D3748'); // Dark Gray
    final textLight = PdfColor.fromHex('#718096'); // Medium Gray

    final isArabic = languageCode == 'ar';
    final textDirection = isArabic
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: pw.EdgeInsets.zero, // Edge-to-edge design
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
          fontFallback: [fallbackFont],
        ),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: textDirection,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Premium Top Header Banner
                pw.Container(
                  padding: const pw.EdgeInsets.only(
                    top: 30,
                    left: 20,
                    right: 20,
                    bottom: 20,
                  ),
                  decoration: pw.BoxDecoration(
                    color: primaryColor,
                    borderRadius: const pw.BorderRadius.only(
                      bottomLeft: pw.Radius.circular(24),
                      bottomRight: pw.Radius.circular(24),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // Right - Text (Doctor Info)
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              clinic.doctorName ?? clinic.name,
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (clinic.specialization != null)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 4),
                                child: pw.Text(
                                  clinic.specialization!,
                                  style: pw.TextStyle(
                                    color: accentColor,
                                    fontSize: 14,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Left - Icon Area
                      pw.Container(
                        width: 50,
                        height: 50,
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.white,
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.Center(
                          child: pw.Icon(
                            const pw.IconData(0xe548), // Medical Icon
                            color: primaryColor,
                            size: 28,
                            font: iconFont,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Body Content
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Modern Patient Info Card
                        pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(
                            color: surfaceColor,
                            borderRadius: pw.BorderRadius.circular(10),
                            border: pw.Border.all(
                              color: accentColor.withAlpha(0.3),
                              width: 1,
                            ),
                          ),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              _buildModernInfo(
                                isArabic ? 'الاسم' : 'Name',
                                patient.name,
                                textLight,
                                textDark,
                              ),
                              _buildModernInfo(
                                isArabic ? 'السن' : 'Age',
                                '${patient.age}',
                                textLight,
                                textDark,
                              ),
                              _buildModernInfo(
                                isArabic ? 'التاريخ' : 'Date',
                                DateFormat('yyyy/MM/dd').format(record.date),
                                textLight,
                                textDark,
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 20),

                        // Rx Header with subtle line
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              'Rx',
                              style: pw.TextStyle(
                                color: primaryColor,
                                fontSize: 26,
                                fontWeight: pw.FontWeight.bold,
                                fontItalic: fallbackFont,
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            pw.Expanded(
                              child: pw.Container(
                                height: 1.5,
                                color: accentColor.withAlpha(0.2),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 15),

                        // Medications List
                        pw.Expanded(
                          child: pw.ListView.builder(
                            itemCount: record.medications.length,
                            itemBuilder: (context, index) {
                              final med = record.medications[index];
                              return pw.Container(
                                margin: const pw.EdgeInsets.only(bottom: 12),
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  borderRadius: pw.BorderRadius.circular(8),
                                  border: pw.Border(
                                    left: pw.BorderSide(
                                      color: accentColor,
                                      width: 3,
                                    ), // Accent bar on the side
                                    top: pw.BorderSide(
                                      color: surfaceColor,
                                      width: 1,
                                    ),
                                    right: pw.BorderSide(
                                      color: surfaceColor,
                                      width: 1,
                                    ),
                                    bottom: pw.BorderSide(
                                      color: surfaceColor,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.stretch,
                                  children: [
                                    pw.Directionality(
                                      textDirection: pw.TextDirection.ltr,
                                      child: pw.Text(
                                        med.name,
                                        style: pw.TextStyle(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 15,
                                          color: textDark,
                                        ),
                                      ),
                                    ),
                                    if (med.instructions.isNotEmpty)
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.only(
                                          top: 6,
                                        ),
                                        child: pw.Directionality(
                                          textDirection: pw.TextDirection.rtl,
                                          child: pw.Text(
                                            med.instructions,
                                            textAlign: pw.TextAlign.right,
                                            style: pw.TextStyle(
                                              fontSize: 13,
                                              color: textLight,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Consultation Notice
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 8),
                          child: pw.Center(
                            child: pw.Text(
                              isArabic
                                  ? 'الاستشارة خلال أسبوع مع ضرورة إحضار الروشتة'
                                  : 'Consultation within a week with prescription',
                              style: pw.TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Premium Footer
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  decoration: pw.BoxDecoration(
                    color: surfaceColor,
                    border: pw.Border(
                      top: pw.BorderSide(
                        color: accentColor.withAlpha(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // Contact Info
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildFooterLine(
                              iconFont,
                              0xe0c8, // Location icon
                              clinic.address ??
                                  (isArabic
                                      ? 'العنوان غير محدد'
                                      : 'Address not set'),
                              accentColor,
                              textDark,
                            ),
                            pw.SizedBox(height: 6),
                            if (clinic.phone != null)
                              _buildFooterLine(
                                iconFont,
                                0xe0b0, // Phone icon
                                isArabic
                                    ? 'محمول: ${clinic.phone}'
                                    : 'Phone: ${clinic.phone}',
                                accentColor,
                                textDark,
                              ),
                          ],
                        ),
                      ),
                      // QR Code
                      pw.Container(
                        width: 45,
                        height: 45,
                        padding: const pw.EdgeInsets.all(2),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(6),
                          border: pw.Border.all(
                            color: accentColor.withAlpha(0.2),
                          ),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: clinic.id,
                          color: primaryColor,
                          drawText: false,
                        ),
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

  static pw.Widget _buildModernInfo(
    String label,
    String value,
    PdfColor lightText,
    PdfColor darkText,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: lightText)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: darkText,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooterLine(
    pw.Font iconFont,
    int iconCode,
    String text,
    PdfColor color,
    PdfColor textColor,
  ) {
    return pw.Row(
      children: [
        pw.Icon(pw.IconData(iconCode), font: iconFont, color: color, size: 14),
        pw.SizedBox(width: 8),
        pw.Text(text, style: pw.TextStyle(fontSize: 11, color: textColor)),
      ],
    );
  }
}
