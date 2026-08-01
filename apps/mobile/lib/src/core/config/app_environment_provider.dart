import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_environment.dart';

final appEnvironmentProvider = Provider<AppEnvironment>(
  (_) => AppEnvironment.fromDefines(),
);
