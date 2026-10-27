/// Android-only permissions for continuous and operation CPU holds.
class CpuSleepOptions {
  const CpuSleepOptions({
    this.unconditional = false,
    this.always = false,
    this.ble = false,
    this.tcp = false,
    this.proxy = false,
    this.wardrive = false,
  });

  final bool unconditional;
  final bool always;
  final bool ble;
  final bool tcp;
  final bool proxy;
  final bool wardrive;
  bool get enabled => unconditional || always || ble || tcp || proxy || wardrive;

  CpuSleepOptions copyWith({bool? unconditional, bool? always, bool? ble, bool? tcp,
    bool? proxy, bool? wardrive}) => CpuSleepOptions(
      unconditional: unconditional ?? this.unconditional,
      always: always ?? this.always, ble: ble ?? this.ble,
      tcp: tcp ?? this.tcp, proxy: proxy ?? this.proxy,
      wardrive: wardrive ?? this.wardrive,
    );

  factory CpuSleepOptions.fromJson(Object? value) => value is Map
      ? CpuSleepOptions(unconditional: value['unconditional'] == true,
          always: value['always'] == true, ble: value['ble'] == true,
          tcp: value['tcp'] == true, proxy: value['proxy'] == true,
          wardrive: value['wardrive'] == true)
      : const CpuSleepOptions();

  Map<String, bool> toJson() => {
    if (unconditional) 'unconditional': true,
    'always': always, 'ble': ble, 'tcp': tcp,
    'proxy': proxy, 'wardrive': wardrive};

  bool permits({required bool background, required Set<String> scenarios}) {
    if (unconditional || always) return true;
    if (!background || scenarios.isEmpty) return false;
    return scenarios.every((scenario) => switch (scenario) {
      'ble' => ble, 'tcp' => tcp, 'proxy' => proxy, 'wardrive' => wardrive,
      _ => false,
    });
  }
}
