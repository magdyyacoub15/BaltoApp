import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../auth/domain/models/clinic_group.dart';
import '../domain/models/medical_record.dart';
import '../domain/patient.dart';
import 'package:intl/intl.dart';

class PrescriptionService {
  static Future<void> printPrescription({
    required ClinicGroup clinic,
    required Patient patient,
    required MedicalRecord record,
    required String languageCode,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansArabicRegular();
    final boldFont = await PdfGoogleFonts.notoSansArabicBold();
    final iconFont = await PdfGoogleFonts.materialIcons();

    final PdfColor primaryColor = PdfColor.fromHex('#D32F2F'); // Dark Red
    final PdfColor bgColor = PdfColor.fromHex('#FFF5F5'); // Light Pink
    final PdfColor textColor = PdfColors.grey900;

    final isArabic = languageCode == 'ar';
    final textDirection = isArabic
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: textDirection,
            child: pw.Container(
              color: bgColor,
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Header (Double)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Left - English
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              clinic.doctorName ?? clinic.name,
                              style: pw.TextStyle(
                                fontSize: 18,
                                color: primaryColor,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (clinic.specialization != null) ...[
                              pw.Text(
                                'Specialist of Cardiology', // Default Example if needed
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              ),
                              pw.Text(
                                'M.B.BCH',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Right - Arabic
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              clinic.doctorName ?? clinic.name,
                              textDirection: pw.TextDirection.rtl,
                              style: pw.TextStyle(
                                fontSize: 18,
                                color: primaryColor,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (clinic.specialization != null) ...[
                              pw.Text(
                                clinic.specialization!,
                                textDirection: pw.TextDirection.rtl,
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              ),
                              pw.Text(
                                'ماجستير الأمراض الباطنية',
                                textDirection: pw.TextDirection.rtl,
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),

                    // Heartbeat Pulse Line Divider
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(
                            height: 2,
                            color: primaryColor.withAlpha(50),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          child: pw.Container(
                            width: 60,
                            height: 30,
                            child: pw.SvgImage(
                              svg: '''
<svg viewBox="0 0 100 50">
  <path d="M0 25 H40 L45 15 L50 35 L55 20 L60 25 H100" stroke="#D32F2F" stroke-width="3" fill="none"/>
  <path d="M50 25 m-5 0 a5 5 0 1 0 10 0 a5 5 0 1 0 -10 0" fill="#D32F2F"/>
</svg>
''',
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Container(
                            height: 2,
                            color: primaryColor.withAlpha(50),
                          ),
                        ),
                      ],
                    ),

                    pw.SizedBox(height: 15),

                    // Patient Info Bar
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: primaryColor, width: 2),
                          bottom: pw.BorderSide(color: primaryColor, width: 2),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _buildInfoField(
                            isArabic ? "الاسم" : "Name",
                            patient.name,
                            isArabic,
                          ),
                          _buildInfoField(
                            isArabic ? "السن" : "Age",
                            "${patient.age}",
                            isArabic,
                          ),
                          _buildInfoField(
                            isArabic ? "التاريخ" : "Date",
                            DateFormat('yyyy/MM/dd').format(record.date),
                            isArabic,
                          ),
                          _buildInfoField(
                            isArabic ? "الاستشارة" : "Consultation",
                            "/  /",
                            isArabic,
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 20),

                    // Rx and Vital Icons Row
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Rx Symbol
                        pw.Text(
                          'Rx',
                          style: pw.TextStyle(
                            fontSize: 48,
                            fontWeight: pw.FontWeight.bold,
                            fontItalic:
                                font, // Try using a different font style if possible
                            color: primaryColor,
                          ),
                        ),
                        // Vital Icons placeholder (BP, Glucose, Heart)
                        pw.Column(
                          children: [
                            _buildVitalIcon(PdfColors.black, 'BP'),
                            pw.SizedBox(height: 10),
                            _buildVitalIcon(PdfColors.black, 'Sugar'),
                            pw.SizedBox(height: 10),
                            _buildVitalIcon(PdfColors.black, 'Heart'),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),

                    // Medications
                    pw.Expanded(
                      child: pw.ListView.builder(
                        itemCount: record.medications.length,
                        itemBuilder: (context, index) {
                          final med = record.medications[index];
                          return pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 5),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  '${index + 1}. ${med.name}',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 15),
                                  child: pw.Text(
                                    '${med.dosage} - ${med.frequency} (${med.duration})',
                                    style: const pw.TextStyle(
                                      fontSize: 11,
                                      color: PdfColors.grey700,
                                    ),
                                  ),
                                ),
                                if (med.instructions.isNotEmpty)
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.only(left: 15),
                                    child: pw.Text(
                                      'Note: ${med.instructions}',
                                      style: pw.TextStyle(
                                        fontSize: 10,
                                        fontStyle: pw.FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    pw.SizedBox(height: 20),
                    // Colored Footer
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: bgColor,
                        border: pw.Border(
                          top: pw.BorderSide(color: primaryColor, width: 2),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          // Left - Contacts
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                children: [
                                  pw.Text(
                                    clinic.phone ?? "",
                                    style: const pw.TextStyle(fontSize: 10),
                                  ),
                                  pw.SizedBox(width: 5),
                                  pw.Icon(
                                    const pw.IconData(0xe0b0),
                                    font: iconFont,
                                    size: 12,
                                    color: primaryColor,
                                  ),
                                ],
                              ),
                              pw.Row(
                                children: [
                                  pw.Text(
                                    clinic.phone ?? "",
                                    style: const pw.TextStyle(fontSize: 10),
                                  ),
                                  pw.SizedBox(width: 5),
                                  pw.Icon(
                                    const pw.IconData(
                                      0xe8af,
                                    ), // Whatsapp-like icon or generic chat
                                    font: iconFont,
                                    size: 12,
                                    color: PdfColors.green,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Center - Address
                          pw.Expanded(
                            child: pw.Text(
                              clinic.address ?? "Clinic Address",
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          // Right - QR Code
                          pw.Container(
                            width: 40,
                            height: 40,
                            child: pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: clinic.id,
                              drawText: false,
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
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  static pw.Widget _buildInfoField(String label, String value, bool isArabic) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  static pw.Widget _buildVitalIcon(PdfColor color, String label) {
    // Simplified icons for now
    return pw.Container(
      width: 25,
      height: 25,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        shape: pw.BoxShape.circle,
      ),
      child: pw.Center(
        child: pw.Text(
          label[0],
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
