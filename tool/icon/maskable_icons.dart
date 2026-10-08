// Writes web/icons/Icon-maskable-{192,512}.png from the icon master with
// safe-zone padding (Phase A, E3). flutter_launcher_icons 0.14.4 makes the
// maskable icons a plain resize of the master, which puts the bus outside the
// maskable safe zone (a circle of 40 % of the icon's width around its
// centre). Run after the generator, from the repository root:
//   dart run tool/icon/maskable_icons.dart
// The master is only read. The padding repeats the master's own background
// colour, so no new colour is introduced.
import 'dart:io';
import 'dart:typed_data';

const master = 'tool/icon/app_icon_master.png';

/// The master is centred on a canvas this much wider: the outermost essential
/// pixel (the bus's rear corner, about 0.45 of the master's width from its
/// centre) then lands at 0.39 of the icon, inside the 0.40 safe zone.
const padFactor = 1.16;

void main() {
  final src = decodeRgbPng(File(master).readAsBytesSync());
  final side = (src.width * padFactor).round();
  final offset = (side - src.width) ~/ 2;
  final canvas = Uint8List(side * side * 3);
  for (var i = 0; i < side * side; i++) {
    canvas.setRange(i * 3, i * 3 + 3, src.pixels, 0); // the corner colour
  }
  for (var y = 0; y < src.height; y++) {
    canvas.setRange(
      ((y + offset) * side + offset) * 3,
      ((y + offset) * side + offset + src.width) * 3,
      src.pixels,
      y * src.width * 3,
    );
  }
  for (final size in [192, 512]) {
    final out = 'web/icons/Icon-maskable-$size.png';
    File(out).writeAsBytesSync(
      encodeRgbPng(size, size, boxDownscale(canvas, side, size)),
    );
    stdout.writeln('wrote $out ($size × $size, master padded to $side px)');
  }
}

/// Averages the source pixels that fall in each output pixel's box.
Uint8List boxDownscale(Uint8List rgb, int from, int to) {
  final out = Uint8List(to * to * 3);
  for (var oy = 0; oy < to; oy++) {
    final y0 = oy * from ~/ to, y1 = (oy + 1) * from ~/ to;
    for (var ox = 0; ox < to; ox++) {
      final x0 = ox * from ~/ to, x1 = (ox + 1) * from ~/ to;
      final sum = [0, 0, 0];
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          for (var c = 0; c < 3; c++) {
            sum[c] += rgb[(y * from + x) * 3 + c];
          }
        }
      }
      final n = (y1 - y0) * (x1 - x0);
      for (var c = 0; c < 3; c++) {
        out[(oy * to + ox) * 3 + c] = (sum[c] / n).round();
      }
    }
  }
  return out;
}

/// An 8-bit RGB, non-interlaced PNG (the master's format), as raw pixels.
({int width, int height, Uint8List pixels}) decodeRgbPng(Uint8List b) {
  final data = ByteData.sublistView(b);
  final width = data.getUint32(16), height = data.getUint32(20);
  if (b[24] != 8 || b[25] != 2 || b[28] != 0) {
    throw const FormatException('expected an 8-bit RGB, non-interlaced PNG');
  }
  final idat = BytesBuilder();
  for (var i = 8; i < b.length;) {
    final n = data.getUint32(i);
    if (String.fromCharCodes(b.sublist(i + 4, i + 8)) == 'IDAT') {
      idat.add(b.sublist(i + 8, i + 8 + n));
    }
    i += 12 + n;
  }
  final raw = zlib.decode(idat.takeBytes());
  const bpp = 3;
  final stride = width * bpp;
  final px = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    for (var x = 0; x < stride; x++) {
      final v = raw[y * (stride + 1) + 1 + x];
      final a = x >= bpp ? px[y * stride + x - bpp] : 0;
      final up = y > 0 ? px[(y - 1) * stride + x] : 0;
      final c = x >= bpp && y > 0 ? px[(y - 1) * stride + x - bpp] : 0;
      final p = a + up - c;
      final pa = (p - a).abs(), pb = (p - up).abs(), pc = (p - c).abs();
      final predictor = switch (filter) {
        0 => 0,
        1 => a,
        2 => up,
        3 => (a + up) >> 1,
        4 => pa <= pb && pa <= pc ? a : (pb <= pc ? up : c),
        _ => throw FormatException('bad PNG filter $filter'),
      };
      px[y * stride + x] = (v + predictor) & 0xff;
    }
  }
  return (width: width, height: height, pixels: px);
}

/// An 8-bit RGB PNG with filter 0 on every row.
Uint8List encodeRgbPng(int width, int height, Uint8List rgb) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(rgb.sublist(y * width * 3, (y + 1) * width * 3));
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibEncoder(level: 9).convert(raw.takeBytes())))
        ..add(_chunk('IEND', const [])))
      .takeBytes();
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final head = ByteData(4)..setUint32(0, data.length);
  final tail = ByteData(4)..setUint32(0, _crc32(body));
  return [...head.buffer.asUint8List(), ...body, ...tail.buffer.asUint8List()];
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
