import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../../core/localization/language_provider.dart';

class PrescriptionPreviewScreen extends ConsumerWidget {
  final Uint8List pdfBytes;
  final String title;

  const PrescriptionPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isNotEmpty ? title : ref.tr('print_preview')),
        elevation: 0,
      ),
      body: PdfPreview(
        build: (format) => pdfBytes,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        initialPageFormat: PdfPageFormat.a5,
        pdfFileName: '$title.pdf',
      ),
    );
  }
}
