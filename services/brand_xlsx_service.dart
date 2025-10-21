// lib/services/brand_xlsx_service.dart
//
// Exportador XLSX (OOXML) con fotos embebidas a la derecha:
// - Corrección EXIF (orientación) + GPS EXIF como fallback.
// - Hipervínculo a Google Maps en columna Lat.
// - Encabezado congelado + autofiltro.
// - Lat/Lng con formato 0.000000.
// - Título/headers con esquema oscuro.
// - docProps incluidos para mayor compatibilidad (Gmail/Outlook/Sheets).
//
// Requiere en pubspec: archive, intl, path, path_provider, image

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BrandExportResult {
  final File xlsxFile;
  final File cacheCopy;
  const BrandExportResult({required this.xlsxFile, required this.cacheCopy});
}

class Geo {
  final double? lat;
  final double? lng;
  const Geo(this.lat, this.lng);
}

class BrandXlsxService {
  const BrandXlsxService();

  Future<BrandExportResult> export({
    required String sheetTitle,
    required List<String> baseHeaders,
    required List<List<String>> baseRows,
    required Map<int, List<String>> imagesByRow,
    List<Geo?>? coordsByRow,
    int photoColumns = 3,
    // Colores ARGB (sin #) para tema oscuro
    String colorTitleBg = 'FF000000',
    String colorHeaderBg = 'FF1E1E1E',
    String colorCellBg = 'FF2B2B2B',
    String colorFont = 'FFFFFFFF',
    // Métricas
    double dataColWidth = 18.0,
    double coordColWidth = 12.0,
    double photoColWidth = 26.0,
    double rowHeightNormal = 18.0,
    double rowHeightWithPhoto = 88.0,
    double headerHeight = 22.0,
    double titleHeight = 26.0,
    double photoWidthPx = 128.0,
    double photoHeightPx = 96.0,
  }) async {
    final safeTitle = _sanitizeSheetName(sheetTitle);
    if (baseHeaders.isEmpty) {
      throw ArgumentError('baseHeaders no puede ser vacío.');
    }
    for (final r in baseRows) {
      if (r.length != baseHeaders.length) {
        throw ArgumentError('Todas las filas deben tener ${baseHeaders.length} columnas.');
      }
    }
    final int safePhotoCols = photoColumns.clamp(0, 10);

    // Normalizar imágenes y tomar GPS EXIF si falta.
    final Map<int, List<_PreparedImage>> normalizedImages = {};
    for (final entry in imagesByRow.entries) {
      final r = entry.key;
      if (r < 0 || r >= baseRows.length) continue;

      final list = <_PreparedImage>[];
      final limit = min(entry.value.length, safePhotoCols);
      for (var i = 0; i < limit; i++) {
        final path = entry.value[i];
        final f = File(path);
        if (!f.existsSync()) continue;
        try {
          final fileBytes = f.readAsBytesSync();
          final prep = _prepareImage(
            fileBytes,
            originalPath: path,
            targetWidthPx: photoWidthPx,
            targetHeightPx: photoHeightPx,
          );
          list.add(prep);

          final needsGps = coordsByRow == null || coordsByRow.length <= r || coordsByRow[r] == null;
          if (needsGps && prep.exifGps != null) {
            final tmp = (coordsByRow ?? List<Geo?>.filled(baseRows.length, null, growable: false))
                .toList(growable: false);
            tmp[r] = Geo(prep.exifGps!.lat, prep.exifGps!.lng);
            coordsByRow = tmp;
          }
        } catch (_) {}
      }
      if (list.isNotEmpty) normalizedImages[r] = list;
    }

    final bytes = _generateXlsxBytes(
      sheetTitle: safeTitle,
      baseHeaders: baseHeaders,
      baseRows: baseRows,
      normalizedImages: normalizedImages,
      coordsByRow: coordsByRow,
      photoColumns: safePhotoCols,
      colorTitleBg: colorTitleBg,
      colorHeaderBg: colorHeaderBg,
      colorCellBg: colorCellBg,
      colorFont: colorFont,
      dataColWidth: dataColWidth,
      coordColWidth: coordColWidth,
      photoColWidth: photoColWidth,
      headerHeight: headerHeight,
      titleHeight: titleHeight,
      rowHeightNormal: rowHeightNormal,
      rowHeightWithPhoto: rowHeightWithPhoto,
      photoWidthPx: photoWidthPx,
      photoHeightPx: photoHeightPx,
    );

    final docs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(docs.path, 'exports'));
    if (!await exportsDir.exists()) await exportsDir.create(recursive: true);

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fname = '${_sanitizeFileBase(safeTitle)}_$ts.xlsx';
    final out = File(p.join(exportsDir.path, fname))..writeAsBytesSync(bytes, flush: true);

    final cacheDir = await getTemporaryDirectory();
    final cacheCopy = File(p.join(cacheDir.path, fname))..writeAsBytesSync(bytes, flush: true);

    return BrandExportResult(xlsxFile: out, cacheCopy: cacheCopy);
  }

  // ----------------------------------------------------------------

  Uint8List _generateXlsxBytes({
    required String sheetTitle,
    required List<String> baseHeaders,
    required List<List<String>> baseRows,
    required Map<int, List<_PreparedImage>> normalizedImages,
    required List<Geo?>? coordsByRow,
    required int photoColumns,
    required String colorTitleBg,
    required String colorHeaderBg,
    required String colorCellBg,
    required String colorFont,
    required double dataColWidth,
    required double coordColWidth,
    required double photoColWidth,
    required double headerHeight,
    required double titleHeight,
    required double rowHeightNormal,
    required double rowHeightWithPhoto,
    required double photoWidthPx,
    required double photoHeightPx,
  }) {
    final archive = Archive();
    final nowUtc = DateTime.now().toUtc();

    final int dataCols = baseHeaders.length;
    const int latLngCols = 2;
    final int totalPhotoCols = photoColumns;

    final headers = <String>[
      ...baseHeaders,
      'Lat',
      'Lng',
      ...List<String>.generate(totalPhotoCols, (i) => 'Foto ${i + 1}'),
    ];

    final rows = <List<_CellVal>>[];
    final rowsWithPhoto = <int>{};

    for (var r = 0; r < baseRows.length; r++) {
      final base = baseRows[r];
      final Geo? geo = (coordsByRow != null && r < coordsByRow.length) ? coordsByRow[r] : null;

      rows.add(<_CellVal>[
        ...base.map<_CellVal>((e) => _CellVal.text(e)),
        _CellVal.num(geo?.lat),
        _CellVal.num(geo?.lng),
        ...List<_CellVal>.filled(totalPhotoCols, _CellVal.text('')),
      ]);

      if ((normalizedImages[r] ?? const <_PreparedImage>[]).isNotEmpty) {
        rowsWithPhoto.add(r);
      }
    }

    // Construcción de imágenes
    final placements = <_PicPlacement>[];
    final mediaRels = <_MediaRel>[];
    var mediaIndex = 1;

    final int photoStartCol0 = dataCols + latLngCols; // 0-based
    for (var r = 0; r < baseRows.length; r++) {
      final imgs = normalizedImages[r] ?? const <_PreparedImage>[];
      if (imgs.isEmpty) continue;

      for (var j = 0; j < imgs.length && j < totalPhotoCols; j++) {
        final prep = imgs[j];
        final mediaName = 'image$mediaIndex.${prep.ext}';
        mediaIndex++;

        archive.addFile(ArchiveFile('xl/media/$mediaName', prep.bytes.length, prep.bytes));

        final relId = 'rId${mediaRels.length + 1}';
        mediaRels.add(_MediaRel(relId, 'media/$mediaName', prep.ext));

        // Anchors 0-based
        final excelRow0 = (r + 2);
        final excelCol0 = photoStartCol0 + j;

        const emu = 9525; // px -> EMUs
        final cx = (photoWidthPx * emu).round();
        final cy = (photoHeightPx * emu).round();

        placements.add(_PicPlacement(
          row0: excelRow0,
          col0: excelCol0,
          relId: relId,
          picId: placements.length + 1,
          cx: cx,
          cy: cy,
        ));
      }
    }

    // Hipervínculos a Maps en columna Lat
    final int latCol0 = dataCols;
    final linkRels = <_HyperlinkRel>[];
    final hyperlinks = <_HyperlinkRef>[];
    var nextHyperRid = 1;
    for (var r = 0; r < rows.length; r++) {
      final lat = rows[r][latCol0].asNum;
      final lng = rows[r][latCol0 + 1].asNum;
      if (lat == null || lng == null) continue;
      final url = 'https://maps.google.com/?q=${_fmt6(lat)},${_fmt6(lng)}';
      final rid = 'hrId${nextHyperRid++}';
      linkRels.add(_HyperlinkRel(id: rid, target: url));
      final rowExcel = r + 3;
      final latCellRef = '${_colName(latCol0)}$rowExcel';
      hyperlinks.add(_HyperlinkRef(cellRef: latCellRef, relId: rid));
    }

    // XML
    final contentTypesXml = _contentTypesXml(
      includeDrawing: placements.isNotEmpty,
      includeSharedStrings: false,
    );
    final relsRootXml = _relsRootXml();
    final workbookXml = _workbookXml(sheetTitle);
    final workbookRelsXml = _workbookRelsXml();
    final stylesXml = _stylesXml(
      colorTitleBg: colorTitleBg,
      colorHeaderBg: colorHeaderBg,
      colorCellBg: colorCellBg,
      colorFont: colorFont,
    );
    final sheetXml = _sheetXml(
      title: sheetTitle,
      headers: headers,
      rows: rows,
      dataCols: dataCols,
      coordCols: latLngCols,
      photoCols: totalPhotoCols,
      dataColWidth: dataColWidth,
      coordColWidth: coordColWidth,
      photoColWidth: photoColWidth,
      headerHeight: headerHeight,
      titleHeight: titleHeight,
      rowHeightNormal: rowHeightNormal,
      rowHeightWithPhoto: rowHeightWithPhoto,
      rowsWithPhoto: rowsWithPhoto,
      hasDrawings: placements.isNotEmpty,
      hyperlinks: hyperlinks,
    );

    String? sheetRelsXml;
    if (placements.isNotEmpty || linkRels.isNotEmpty) {
      final rels = <String>[];
      if (placements.isNotEmpty) {
        rels.add(
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>',
        );
      }
      for (final lr in linkRels) {
        rels.add(
          '<Relationship Id="${lr.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_xml(lr.target)}" TargetMode="External"/>',
        );
      }
      sheetRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  ${rels.join('\n  ')}
</Relationships>
''';
    }

    String? drawingXml;
    String? drawingRelsXml;
    if (placements.isNotEmpty) {
      drawingXml = _drawingXml(placements);
      drawingRelsXml = _drawingRelsXml(mediaRels);
    }

    final appPropsXml = _appPropsXml(sheetTitle);
    final corePropsXml = _corePropsXml(nowUtc);

    // ZIP
    void addText(String path, String xml) {
      final data = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, data.length, data));
    }

    addText('[Content_Types].xml', contentTypesXml);
    addText('_rels/.rels', relsRootXml);
    addText('docProps/app.xml', appPropsXml);
    addText('docProps/core.xml', corePropsXml);
    addText('xl/workbook.xml', workbookXml);
    addText('xl/_rels/workbook.xml.rels', workbookRelsXml);
    addText('xl/styles.xml', stylesXml);
    addText('xl/worksheets/sheet1.xml', sheetXml);
    if (sheetRelsXml != null) {
      addText('xl/worksheets/_rels/sheet1.xml.rels', sheetRelsXml);
    }
    if (drawingXml != null) addText('xl/drawings/drawing1.xml', drawingXml);
    if (drawingRelsXml != null) {
      addText('xl/drawings/_rels/drawing1.xml.rels', drawingRelsXml);
    }

    final out = ZipEncoder().encode(archive);
    return Uint8List.fromList(out);
  }

  // -------------------- XML builders --------------------

  String _contentTypesXml({
    required bool includeDrawing,
    required bool includeSharedStrings,
  }) {
    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..writeln('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..writeln('<Default Extension="xml" ContentType="application/xml"/>')
      ..writeln('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..writeln('<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
      ..writeln('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
      ..writeln('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
      ..writeln('<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    if (includeSharedStrings) {
      sb.writeln('<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>');
    }
    sb
      ..writeln('<Default Extension="png" ContentType="image/png"/>')
      ..writeln('<Default Extension="jpeg" ContentType="image/jpeg"/>')
      ..writeln('<Default Extension="jpg" ContentType="image/jpeg"/>');
    if (includeDrawing) {
      sb.writeln('<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>');
    }
    sb.writeln('</Types>');
    return sb.toString();
  }

  String _relsRootXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

  String _workbookXml(String sheetName) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="${_xml(sheetName)}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
''';

  String _workbookRelsXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''';

  // s=0 título, s=1 header, s=2 texto, s=3 número lat/lng
  String _stylesXml({
    required String colorTitleBg,
    required String colorHeaderBg,
    required String colorCellBg,
    required String colorFont,
  }) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1">
    <numFmt numFmtId="175" formatCode="0.000000"/>
  </numFmts>
  <fonts count="2">
    <font><name val="Calibri"/><sz val="11"/><color rgb="$colorFont"/><b/></font>
    <font><name val="Calibri"/><sz val="11"/><color rgb="$colorFont"/></font>
  </fonts>
  <fills count="4">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="$colorTitleBg"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="$colorHeaderBg"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="$colorCellBg"/></patternFill></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="1" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="4">
    <xf numFmtId="0" fontId="0" fillId="1" borderId="0" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="0" fillId="2" borderId="0" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="1" fillId="3" borderId="0" applyFill="1"/>
    <xf numFmtId="175" fontId="1" fillId="3" borderId="0" applyFill="1" applyNumberFormat="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
''';

  String _sheetXml({
    required String title,
    required List<String> headers,
    required List<List<_CellVal>> rows,
    required int dataCols,
    required int coordCols,
    required int photoCols,
    required double dataColWidth,
    required double coordColWidth,
    required double photoColWidth,
    required double headerHeight,
    required double titleHeight,
    required double rowHeightNormal,
    required double rowHeightWithPhoto,
    required Set<int> rowsWithPhoto,
    required bool hasDrawings,
    required List<_HyperlinkRef> hyperlinks,
  }) {
    final totalCols = headers.length;
    final totalRows = rows.length + 2; // título+header
    final lastColRef = _colName(totalCols - 1);
    final dim = 'A1:$lastColRef$totalRows';

    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.writeln('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');

    sb.writeln('<dimension ref="$dim"/>');

    sb.writeln('<sheetViews><sheetView workbookViewId="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');

    // Columnas
    sb.write('<cols>');
    if (dataCols > 0) {
      sb.write('<col min="1" max="$dataCols" width="$dataColWidth" customWidth="1"/>');
    }
    final latStart = dataCols + 1;
    final latEnd = dataCols + coordCols;
    sb.write('<col min="$latStart" max="$latEnd" width="$coordColWidth" customWidth="1"/>');
    if (photoCols > 0) {
      final photoStart = dataCols + coordCols + 1;
      final photoEnd = dataCols + coordCols + photoCols;
      sb.write('<col min="$photoStart" max="$photoEnd" width="$photoColWidth" customWidth="1"/>');
    }
    sb.writeln('</cols>');

    sb.writeln('<sheetData>');

    // Título
    sb.writeln('<row r="1" ht="$titleHeight" customHeight="1">');
    sb.writeln('<c r="A1" t="inlineStr" s="0"><is><t>${_xml(title)}</t></is></c>');
    sb.writeln('</row>');

    // Encabezados
    sb.writeln('<row r="2" ht="$headerHeight" customHeight="1">');
    for (var c = 0; c < totalCols; c++) {
      final ref = '${_colName(c)}2';
      sb.writeln('<c r="$ref" t="inlineStr" s="1"><is><t>${_xml(headers[c])}</t></is></c>');
    }
    sb.writeln('</row>');

    // Datos
    for (var r = 0; r < rows.length; r++) {
      final excelRow = r + 3;
      final hasPhoto = rowsWithPhoto.contains(r);
      final ht = hasPhoto ? rowHeightWithPhoto : rowHeightNormal;

      sb.writeln('<row r="$excelRow" ht="$ht" customHeight="1">');
      for (var c = 0; c < totalCols; c++) {
        final ref = '${_colName(c)}$excelRow';
        final val = rows[r][c];
        // Lat/Lng numéricos con estilo s=3
        if (c == dataCols || c == dataCols + 1) {
          if (val.asNum == null) {
            sb.writeln('<c r="$ref" s="3"/>');
          } else {
            sb.writeln('<c r="$ref" s="3"><v>${val.asNum}</v></c>');
          }
        } else {
          final txt = val.asText ?? '';
          sb.writeln('<c r="$ref" t="inlineStr" s="2"><is><t>${_xml(txt)}</t></is></c>');
        }
      }
      sb.writeln('</row>');
    }

    sb.writeln('</sheetData>');

    // Merge del título
    final mergeRef = 'A1:${lastColRef}1';
    sb.writeln('<mergeCells count="1"><mergeCell ref="$mergeRef"/></mergeCells>');

    // Hipervínculos a Maps
    if (hyperlinks.isNotEmpty) {
      sb.writeln('<hyperlinks>');
      for (final h in hyperlinks) {
        sb.writeln('<hyperlink ref="${h.cellRef}" r:id="${h.relId}"/>');
      }
      sb.writeln('</hyperlinks>');
    }

    // Autofiltro
    sb.writeln('<autoFilter ref="A2:$lastColRef$totalRows"/>');

    // Dibujo de fotos
    if (hasDrawings) {
      sb.writeln('<drawing r:id="rId1"/>');
    }

    sb.writeln('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');

    sb.writeln('</worksheet>');
    return sb.toString();
  }

  String _drawingXml(List<_PicPlacement> pics) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.writeln('<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    for (final p in pics) {
      sb.writeln('<xdr:oneCellAnchor>');
      sb.writeln('  <xdr:from><xdr:col>${p.col0}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${p.row0}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>');
      sb.writeln('  <xdr:ext cx="${p.cx}" cy="${p.cy}"/>');
      sb.writeln('  <xdr:pic>');
      sb.writeln('    <xdr:nvPicPr><xdr:cNvPr id="${p.picId}" name="Picture ${p.picId}"/><xdr:cNvPicPr/></xdr:nvPicPr>');
      sb.writeln('    <xdr:blipFill><a:blip r:embed="${p.relId}" cstate="print"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>');
      sb.writeln('    <xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>');
      sb.writeln('  </xdr:pic>');
      sb.writeln('  <xdr:clientData/>');
      sb.writeln('</xdr:oneCellAnchor>');
    }
    sb.writeln('</xdr:wsDr>');
    return sb.toString();
  }

  String _drawingRelsXml(List<_MediaRel> rels) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (final r in rels) {
      sb.writeln('<Relationship Id="${r.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="${r.target}"/>');
    }
    sb.writeln('</Relationships>');
    return sb.toString();
  }

  String _appPropsXml(String sheetTitle) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Gridnote</Application>
  <DocSecurity>0</DocSecurity>
  <ScaleCrop>false</ScaleCrop>
  <HeadingPairs>
    <vt:vector size="2" baseType="variant">
      <vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant>
      <vt:variant><vt:i4>1</vt:i4></vt:variant>
    </vt:vector>
  </HeadingPairs>
  <TitlesOfParts>
    <vt:vector size="1" baseType="lpstr">
      <vt:lpstr>${_xml(sheetTitle)}</vt:lpstr>
    </vt:vector>
  </TitlesOfParts>
  <Company>Gridnote</Company>
  <LinksUpToDate>false</LinksUpToDate>
  <SharedDoc>false</SharedDoc>
  <HyperlinksChanged>false</HyperlinksChanged>
  <AppVersion>16.0300</AppVersion>
</Properties>
''';

  String _corePropsXml(DateTime nowUtc) {
    final ts = '${nowUtc.toIso8601String().replaceFirst(RegExp(r'\.\d+'), '')}Z';
    return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:creator>Gridnote</dc:creator>
  <cp:lastModifiedBy>Gridnote</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$ts</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$ts</dcterms:modified>
</cp:coreProperties>
''';
  }

  // -------------------- utils --------------------

  String _colName(int index) {
    var n = index + 1;
    var name = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _fmt6(double v) => v.toStringAsFixed(6);

  String _sanitizeFileBase(String s) {
    final v = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();
    return v.isEmpty ? 'Bitacora' : v;
  }

  String _sanitizeSheetName(String s) {
    if (s.isEmpty) return 'Bitacora';
    var v = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (v.length > 31) v = v.substring(0, 31);
    return v.isEmpty ? 'Bitacora' : v;
  }

  _PreparedImage _prepareImage(
      Uint8List originalBytes, {
        required String originalPath,
        required double targetWidthPx,
        required double targetHeightPx,
      }) {
    final extGuess = _detectExt(originalPath, originalBytes);
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded != null) {
        final exif = _Exif.fromBytes(originalBytes);

        img.Image oriented = decoded;
        final rot = exif.orientationRotationDegrees;
        if (rot != 0) {
          oriented = img.copyRotate(decoded, angle: rot);
        }

        final scaleW = targetWidthPx / oriented.width;
        final scaleH = targetHeightPx / oriented.height;
        final scale = min(1.0, min(scaleW, scaleH));
        img.Image finalImg = oriented;
        if (scale < 1.0) {
          final newW = max(1, (oriented.width * scale).round());
          final newH = max(1, (oriented.height * scale).round());
          finalImg = img.copyResize(oriented, width: newW, height: newH, interpolation: img.Interpolation.cubic);
        }

        final outBytes = Uint8List.fromList(img.encodePng(finalImg));
        return _PreparedImage(bytes: outBytes, ext: 'png', exifGps: exif.gps);
      }
    } catch (_) {}
    return _PreparedImage(bytes: originalBytes, ext: extGuess, exifGps: null);
  }

  String _detectExt(String path, Uint8List bytes) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext == 'png' || ext == 'jpeg' || ext == 'jpg') {
      return ext == 'jpg' ? 'jpeg' : ext;
    }
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpeg';
    return 'png';
  }
}

// -------------------- internos --------------------

class _PreparedImage {
  final Uint8List bytes;
  final String ext; // 'png' / 'jpeg'
  final Geo? exifGps;
  _PreparedImage({required this.bytes, required this.ext, required this.exifGps});
}

class _CellVal {
  final String? asText;
  final double? asNum;
  _CellVal._(this.asText, this.asNum);
  factory _CellVal.text(String? s) => _CellVal._(s ?? '', null);
  factory _CellVal.num(double? n) => _CellVal._(null, n);
}

class _PicPlacement {
  final int row0; // 0-based
  final int col0; // 0-based
  final String relId;
  final int picId;
  final int cx; // EMUs
  final int cy; // EMUs
  _PicPlacement({
    required this.row0,
    required this.col0,
    required this.relId,
    required this.picId,
    required this.cx,
    required this.cy,
  });
}

class _MediaRel {
  final String id; // rIdX
  final String target; // media/imageN.ext
  final String ext; // png / jpeg
  _MediaRel(this.id, this.target, this.ext);
}

class _HyperlinkRel {
  final String id; // hrIdX
  final String target; // URL
  _HyperlinkRel({required this.id, required this.target});
}

class _HyperlinkRef {
  final String cellRef; // "C5"
  final String relId; // hrIdX
  _HyperlinkRef({required this.cellRef, required this.relId});
}

// -------------------- EXIF mínimo --------------------

class _Exif {
  final int orientation; // 1..8
  final Geo? gps;

  _Exif(this.orientation, this.gps);

  int get orientationRotationDegrees {
    switch (orientation) {
      case 3:
        return 180;
      case 6:
        return 90;
      case 8:
        return 270;
      default:
        return 0;
    }
  }

  static _Exif fromBytes(Uint8List bytes) {
    try {
      final parser = _ExifParser(bytes);
      final ori = parser.readOrientation() ?? 1;
      final gps = parser.readGps();
      return _Exif(ori, gps);
    } catch (_) {
      return _Exif(1, null);
    }
  }
}

class _ExifParser {
  final Uint8List bytes;
  _ExifParser(this.bytes);

  int? readOrientation() {
    final info = _locateTiff();
    if (info == null) return null;
    final tiff = info.tiffStart;
    final be = info.bigEndian;
    final ifd0 = tiff + _readUint32(tiff + 4, be);
    final count = _readUint16(ifd0, be);
    for (var i = 0; i < count; i++) {
      final off = ifd0 + 2 + i * 12;
      final tag = _readUint16(off, be);
      if (tag == 0x0112) {
        final type = _readUint16(off + 2, be);
        final cnt = _readUint32(off + 4, be);
        final valOff = off + 8;
        if (type == 3 && cnt >= 1) {
          return _readUint16(valOff, be);
        }
      }
    }
    return null;
  }

  Geo? readGps() {
    final info = _locateTiff();
    if (info == null) return null;
    final tiff = info.tiffStart;
    final be = info.bigEndian;

    final ifd0 = tiff + _readUint32(tiff + 4, be);
    final count = _readUint16(ifd0, be);
    int? gpsIfdOffset;
    for (var i = 0; i < count; i++) {
      final off = ifd0 + 2 + i * 12;
      final tag = _readUint16(off, be);
      if (tag == 0x8825) {
        gpsIfdOffset = _readUint32(off + 8, be);
        break;
      }
    }
    if (gpsIfdOffset == null) return null;
    final gpsIfd = tiff + gpsIfdOffset;
    if (gpsIfd < 0 || gpsIfd >= bytes.length - 2) return null;
    final gpsCount = _readUint16(gpsIfd, be);

    String? nsRef, ewRef;
    List<_Rational>? latR;
    List<_Rational>? lngR;

    for (var i = 0; i < gpsCount; i++) {
      final off = gpsIfd + 2 + i * 12;
      final tag = _readUint16(off, be);
      final type = _readUint16(off + 2, be);
      final cnt = _readUint32(off + 4, be);
      final val = _readUint32(off + 8, be);

      if (tag == 0x0001 && type == 2 && cnt >= 1) {
        final addr = (cnt > 4) ? (tiff + val) : (off + 8);
        nsRef = _readAscii(addr, min(cnt, 4));
      } else if (tag == 0x0002 && type == 5 && cnt == 3) {
        final addr = tiff + val;
        latR = [_readRational(addr, be), _readRational(addr + 8, be), _readRational(addr + 16, be)];
      } else if (tag == 0x0003 && type == 2 && cnt >= 1) {
        final addr = (cnt > 4) ? (tiff + val) : (off + 8);
        ewRef = _readAscii(addr, min(cnt, 4));
      } else if (tag == 0x0004 && type == 5 && cnt == 3) {
        final addr = tiff + val;
        lngR = [_readRational(addr, be), _readRational(addr + 8, be), _readRational(addr + 16, be)];
      }
    }

    if (latR == null || lngR == null || nsRef == null || ewRef == null) return null;

    double dmsToDeg(List<_Rational> v) {
      final d = v[0].toDouble();
      final m = v[1].toDouble();
      final s = v[2].toDouble();
      return d + (m / 60.0) + (s / 3600.0);
    }

    var lat = dmsToDeg(latR);
    var lng = dmsToDeg(lngR);
    if (nsRef.toUpperCase() == 'S') lat = -lat;
    if (ewRef.toUpperCase() == 'W') lng = -lng;

    if (lat.abs() <= 90.0 && lng.abs() <= 180.0) {
      return Geo(lat, lng);
    }
    return null;
  }

  _TiffInfo? _locateTiff() {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) break;
      final marker = bytes[i + 1];
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      if (marker == 0xE1 && i + 4 + len <= bytes.length) {
        if (i + 10 <= bytes.length &&
            bytes[i + 4] == 0x45 &&
            bytes[i + 5] == 0x78 &&
            bytes[i + 6] == 0x69 &&
            bytes[i + 7] == 0x66 &&
            bytes[i + 8] == 0x00 &&
            bytes[i + 9] == 0x00) {
          final tiffStart = i + 10;
          if (tiffStart + 8 <= bytes.length) {
            final bigEndian = (bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D);
            final tag = _readUint16(tiffStart + 2, bigEndian);
            if (tag == 0x002A) {
              return _TiffInfo(tiffStart, bigEndian);
            }
          }
        }
      }
      i += 2 + len;
    }
    return null;
  }

  int _readUint16(int off, bool be) {
    if (off + 1 >= bytes.length) return 0;
    return be ? (bytes[off] << 8) | bytes[off + 1] : (bytes[off + 1] << 8) | bytes[off];
  }

  int _readUint32(int off, bool be) {
    if (off + 3 >= bytes.length) return 0;
    if (be) {
      return (bytes[off] << 24) | (bytes[off + 1] << 16) | (bytes[off + 2] << 8) | bytes[off + 3];
    } else {
      return (bytes[off + 3] << 24) | (bytes[off + 2] << 16) | (bytes[off + 1] << 8) | bytes[off];
    }
  }

  String _readAscii(int off, int len) {
    final end = min(bytes.length, off + len);
    return utf8.decode(bytes.sublist(off, end), allowMalformed: true).replaceAll('\u0000', '');
  }

  _Rational _readRational(int off, bool be) {
    final num = _readUint32(off, be);
    final den = _readUint32(off + 4, be);
    return _Rational(num, den == 0 ? 1 : den);
  }
}

class _TiffInfo {
  final int tiffStart;
  final bool bigEndian;
  _TiffInfo(this.tiffStart, this.bigEndian);
}

class _Rational {
  final int num;
  final int den;
  _Rational(this.num, this.den);
  double toDouble() => den == 0 ? 0.0 : num / den;
}
