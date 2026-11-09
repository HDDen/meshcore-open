import '../connector/meshcore_protocol.dart';

const traceRequestHeaderBytes = 10;
const _legacyTraceFrameSize = 172;

// Official protocol code 13 postdates the increase to 176 bytes. Code 12
// was used on both sides of that change and cannot guarantee a larger frame.
int traceRequestFrameLimit(int? firmwareCode) =>
    (firmwareCode ?? 0) >= 13 ? maxFrameSize : _legacyTraceFrameSize;

int traceRequestHashWidth(int routingHashWidth) =>
    routingHashWidth <= 2 ? routingHashWidth.clamp(1, 2) : 4;

bool traceRequestFits({
  required int hopCount,
  required int wireHashWidth,
  required int? firmwareCode,
}) =>
    hopCount > 0 &&
    hopCount <= maxPathSize &&
    traceRequestHeaderBytes + hopCount * wireHashWidth <=
        traceRequestFrameLimit(firmwareCode);
