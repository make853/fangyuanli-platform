import 'package:fangyuanli_mobile/src/features/plaza/data/gcj02_coordinate_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = MainlandGcj02CoordinateConverter();

  test('北京 WGS-84 样本转换为隔离的 GCJ-02 坐标', () {
    final result = converter.fromWgs84(longitude: 116.397, latitude: 39.908);

    expect(result.longitude, closeTo(116.403243, 0.00005));
    expect(result.latitude, closeTo(39.909403, 0.00005));
  });

  test('广州 WGS-84 样本转换保持在米级容差内', () {
    final result = converter.fromWgs84(
      longitude: 113.264385,
      latitude: 23.129112,
    );

    expect(result.longitude, closeTo(113.269714, 0.00005));
    expect(result.latitude, closeTo(23.126435, 0.00005));
  });

  test('中国大陆范围外不冒充 GCJ-02', () {
    expect(
      () => converter.fromWgs84(longitude: -122.4194, latitude: 37.7749),
      throwsFormatException,
    );
  });
}
