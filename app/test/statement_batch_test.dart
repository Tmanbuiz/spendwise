import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:spendwise/services/statement_import_service.dart';
import 'package:spendwise/data/models/app_transaction.dart';

void main() {
  test(
    'six PDFs add history once even when statements overlap and are retried',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'statement-batch',
      );
      addTearDown(() => directory.delete(recursive: true));
      var id = 0;
      final service = StatementImportService(idGenerator: () => 'test-${id++}');
      final existing = <AppTransaction>[];
      final files = <File>[];
      for (var i = 1; i <= 6; i++) {
        final document = PdfDocument();
        document.pages.add().graphics.drawString(
          'Statement period: Sep 1 to Sep 30, 2026\n'
          'Sep 1       TIM HORTONS                       4.50\n'
          'Sep $i       SHOP $i                           ${20 + i}.00',
          PdfStandardFont(PdfFontFamily.courier, 10),
          bounds: const Rect.fromLTWH(0, 0, 500, 300),
        );
        final file = File('${directory.path}/statement-$i.pdf');
        await file.writeAsBytes(await document.save());
        document.dispose();
        files.add(file);
      }
      for (var pass = 0; pass < 2; pass++) {
        var inserted = 0;
        for (final file in files) {
          final preview = await service.preview(file, existing: existing);
          expect(preview.result.rows, hasLength(2));
          inserted += preview.willInsert.length;
          for (final tx in service.apply(preview.result, existing: existing)) {
            existing.removeWhere((old) => old.id == tx.id);
            existing.add(tx);
          }
        }
        expect(inserted, pass == 0 ? 7 : 0);
        expect(existing, hasLength(7));
      }
    },
  );
}
